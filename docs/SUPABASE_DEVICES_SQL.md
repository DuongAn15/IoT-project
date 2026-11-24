# SQL Supabase: kiểm tra và bổ sung ràng buộc cho devices

Ngày soạn: 24/11/2026 (UTC+7). Các lệnh chưa được chạy trên Supabase. Bối cảnh và các nguy cơ API: [Device API review](DEVICE_API_REVIEW.md).

Chọn đúng project đang chứa `public.devices`. Chạy mục 1 để xem hiện trạng, sau đó chạy nguyên khối 2 để bổ sung ràng buộc. Khối 2 không tạo lại bảng, không cập nhật/xóa dòng dữ liệu và không thay default cấu hình. Nó có transaction và lock ngắn để tránh ghi đồng thời trong lúc kiểm tra/thêm unique; nếu lỗi thì rollback toàn bộ khối.

## 1. Kiểm tra schema, index, dữ liệu và quyền (read-only)

```sql
-- Cột, kiểu, NOT NULL và default.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'devices'
order by ordinal_position;

-- Primary key, unique và CHECK constraints.
select conname, contype, convalidated, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.devices'::regclass
order by conname;

-- Bao gồm cả unique index không được tạo từ constraint.
select indexname, indexdef
from pg_indexes
where schemaname = 'public' and tablename = 'devices';

-- Trùng MAC sau khi trim/uppercase: hữu ích nếu dữ liệu cũ khác cách viết.
select upper(btrim(mac)) as normalized_mac,
       count(*) as row_count, array_agg(device_id order by device_id) as device_ids
from public.devices
group by upper(btrim(mac))
having count(*) > 1;

-- Những dòng sẽ không đáp ứng các ràng buộc được đề xuất.
select device_id, name, mac
from public.devices
where device_id is null or btrim(device_id) = ''
   or name is null or btrim(name) = ''
   or mac is null or mac !~ '^[0-9A-F]{2}(:[0-9A-F]{2}){5}$';

-- RLS bật chưa? Các policy hiện hữu có thể cho phép truy cập.
select relrowsecurity as rls_enabled, relforcerowsecurity as force_rls
from pg_class
where oid = 'public.devices'::regclass;

select policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'devices';

select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'devices'
order by grantee, privilege_type;
```

Hai query dữ liệu trùng/sai phải trả 0 dòng trước khi chạy khối tiếp theo. Nếu có kết quả, xác định thiết bị đúng trước khi sửa thủ công; không xóa dòng hay đổi MAC tự động để vượt constraint.

## 2. Thêm NOT NULL, unique MAC và CHECK constraints

```sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

lock table public.devices in share row exclusive mode;

do $$
declare
  device_id_att smallint;
  mac_att smallint;
begin
  select attnum into device_id_att
  from pg_attribute
  where attrelid = 'public.devices'::regclass
    and attname = 'device_id' and not attisdropped;

  select attnum into mac_att
  from pg_attribute
  where attrelid = 'public.devices'::regclass
    and attname = 'mac' and not attisdropped;

  -- Không tự thay primary key trên bảng live.
  if device_id_att is null or mac_att is null or not exists (
    select 1 from pg_constraint
    where conrelid = 'public.devices'::regclass
      and contype = 'p'
      and conkey = array[device_id_att]::smallint[]
  ) then
    raise exception 'Expected primary key on device_id and existing mac column; inspect schema first';
  end if;

  if exists (
    select 1 from public.devices
    where device_id is null or btrim(device_id) = ''
       or name is null or btrim(name) = ''
       or mac is null or mac !~ '^[0-9A-F]{2}(:[0-9A-F]{2}){5}$'
  ) then
    raise exception 'Invalid device data; inspect with section 1 before adding constraints';
  end if;

  if exists (
    select 1 from public.devices group by mac having count(*) > 1
  ) then
    raise exception 'Duplicate MAC; resolve device ownership before adding unique';
  end if;

  alter table public.devices
    alter column device_id set not null,
    alter column name set not null,
    alter column mac set not null;

  -- Tái sử dụng unique index hợp lệ chỉ có MAC làm key, nếu đã tồn tại.
  -- Unique index ghép MAC với cột khác hoặc partial index không đủ bảo đảm.
  if not exists (
    select 1 from pg_index
    where indrelid = 'public.devices'::regclass
      and indisunique and indisvalid and indisready
      and indnkeyatts = 1 and indkey[0] = mac_att
      and indpred is null and indexprs is null
  ) then
    alter table public.devices
      add constraint devices_mac_unique unique (mac);
  end if;

  -- Kiểm tra tên và định nghĩa trước khi tái chạy, xem ghi chú bên dưới.
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.devices'::regclass
      and conname = 'devices_device_id_not_blank'
  ) then
    alter table public.devices
      add constraint devices_device_id_not_blank
      check (length(btrim(device_id)) > 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.devices'::regclass
      and conname = 'devices_name_not_blank'
  ) then
    alter table public.devices
      add constraint devices_name_not_blank
      check (length(btrim(name)) > 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.devices'::regclass
      and conname = 'devices_mac_format'
  ) then
    alter table public.devices
      add constraint devices_mac_format
      check (mac ~ '^[0-9A-F]{2}(:[0-9A-F]{2}){5}$');
  end if;
end
$$;

alter table public.devices
  validate constraint devices_device_id_not_blank;
alter table public.devices
  validate constraint devices_name_not_blank;
alter table public.devices
  validate constraint devices_mac_format;

commit;
```

Khối có thể chạy lại với các constraint do chính khối này tạo. Nếu mục 1 cho thấy đã có cùng tên constraint nhưng định nghĩa khác, cần đối chiếu trước: kiểm tra tên không chứng minh định nghĩa tương đương. Nếu bị timeout/lỗi, chạy `ROLLBACK;` để kết thúc transaction còn mở trước khi kiểm tra và chạy lại. Bảng lớn cần kế hoạch tạo index/validate riêng; thời gian lock ở đây phù hợp danh mục nhỏ đã quan sát.

## 3. RLS: chỉ bật sau khi đối chiếu các client đang dùng bảng

Nếu bảng `devices` được thiết kế chỉ cho backend sử dụng service-role, có thể bật RLS bằng khối sau. Client dùng anon/authenticated key và không có policy phù hợp sẽ không truy cập được như trước. Kiểm tra mục 1 trước khi thực hiện để biết các client/policy đang phụ thuộc.

```sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
alter table public.devices enable row level security;
commit;
```

Lệnh này giữ nguyên policy hiện có. Nếu đã có policy cho phép `anon`/`authenticated`, bật RLS không tự loại bỏ quyền truy cập đó; cần review từng policy cụ thể. Không dùng lệnh xóa hàng loạt policy. Service-role bypass RLS nhưng vẫn cần quyền bảng thích hợp. RLS không khắc phục [D06 trong tài liệu review](DEVICE_API_REVIEW.md#d06--chưa-có-xác-thựcphân-quyền-cho-api-thiết-bị-cao): backend public vẫn có thể thực thi request bằng service-role.

## 4. Xác minh sau khi chạy

Chạy lại các query tại mục 1, kiểm tra MAC có unique index hợp lệ, ba cột NOT NULL và các CHECK đã validated. Các trường cấu hình/default và 5 dòng hiện có phải giữ nguyên. Vi phạm unique sẽ sinh PostgreSQL `23505`, phù hợp mapping HTTP 409 của backend; không cần cố insert thiết bị trùng trên DB live để xác minh.

SQL này không sửa logic đồng bộ cấu hình, authentication, app hay firmware. Những phần đó cần thay đổi code và kiểm thử riêng theo D01–D12 trong [tài liệu review](DEVICE_API_REVIEW.md).
