import json
import os
from pathlib import Path
import ssl
import tempfile
import unittest
from unittest.mock import Mock, patch

import simulate_nodes as simulator


class SimulatorConnectionTests(unittest.TestCase):
    def test_explicit_env_and_environment_override(self):
        with tempfile.TemporaryDirectory(dir="/tmp/opencode") as directory:
            path = Path(directory) / "env"
            path.write_text("MQTT_BROKER_HOST=example.invalid\nMQTT_BROKER_PORT=8883\n")
            with patch.dict(os.environ, {"MQTT_BROKER_PORT": "1883"}, clear=True):
                values = simulator.find_and_load_env(str(path))
            self.assertEqual(values["MQTT_BROKER_HOST"], "example.invalid")
            self.assertEqual(values["MQTT_BROKER_PORT"], "1883")

    def test_missing_explicit_file_does_not_fall_back(self):
        with patch.object(simulator.os.path, "exists", return_value=False):
            with self.assertRaises(ValueError):
                simulator.find_and_load_env("missing.env")

    def test_backend_env_is_discovered(self):
        with patch.object(simulator.os.path, "exists", side_effect=lambda p: "adht-weather-backend" in p):
            with patch("builtins.open", unittest.mock.mock_open(read_data="MQTT_BROKER_HOST=example.invalid\n")):
                with patch.dict(os.environ, {}, clear=True):
                    values = simulator.find_and_load_env()
        self.assertEqual(values["MQTT_BROKER_HOST"], "example.invalid")

    def make_node(self, **kwargs):
        return simulator.SimulatedEsp32Node(
            simulator.VIRTUAL_NODE_PROFILES[0],
            "example.invalid", 8883, "test", "test", **kwargs,
        )

    def test_verified_tls_and_background_connection(self):
        with patch.object(simulator.mqtt, "Client") as factory:
            client = factory.return_value
            node = self.make_node()
            context = client.tls_set_context.call_args.args[0]
            self.assertTrue(context.check_hostname)
            self.assertEqual(context.verify_mode, ssl.CERT_REQUIRED)
            client.reconnect_delay_set.assert_called_once_with(min_delay=1, max_delay=30)
            with patch.object(simulator.threading, "Thread"):
                node.start()
            client.connect_async.assert_called_once_with("example.invalid", 8883, keepalive=60)
            client.loop_start.assert_called_once()
            client.connect.assert_not_called()
            self.assertFalse(node.is_connected)
            node._on_connect(client, None, None, 0)
            self.assertTrue(node.is_connected)
            node._on_disconnect(client, None, None, 0, None)
            self.assertFalse(node.is_connected)
            node._on_disconnect(client, None, 0)

    def test_plain_mqtt_does_not_configure_tls(self):
        with patch.object(simulator.mqtt, "Client") as factory:
            node = self.make_node(use_tls=False)
            factory.return_value.tls_set_context.assert_not_called()
            node._log = Mock()
            node._on_connect_fail(node.client, None)
            self.assertFalse(node.is_connected)
            node._log.assert_called_once()

    def test_topics_thresholds_and_v2_minute_log_match_firmware(self):
        with patch.object(simulator.mqtt, "Client") as factory:
            client = factory.return_value
            node = self.make_node(enable_v2=True, deployment_id="dep-test")
            self.assertEqual(node.sys_config["rain_max"], 30.0)
            client.will_set.assert_called_once()
            self.assertEqual(client.will_set.call_args.args[0], "adht/weather/status")

            node._on_connect(client, None, None, 0)
            sub_topics = [c.args[0] for c in client.subscribe.call_args_list]
            self.assertEqual(
                sub_topics,
                ["adht/weather/adht_weather_02/command", "adht/weather/adht_weather_02/config"],
            )

            node._update_physics()
            node._publish_v2_minute_log()
            topic, raw = client.publish.call_args.args[0:2]
            self.assertEqual(topic, "adht/weather/adht_weather_02/telemetry/log")
            payload = json.loads(raw)
            self.assertEqual(payload["schema_version"], 2)
            self.assertEqual(payload["deployment_id"], "dep-test")
            self.assertEqual(payload["window_sequence"], 1)

            node._handle_command("reset_rain", "")
            self.assertEqual(node.rain_reset_epoch, 1)
            self.assertEqual(node.rain_tip_counter, 0)
            self.assertEqual(node.rain_total, 0.0)

    def _deliver(self, node, topic: str, payload: dict):
        msg = Mock()
        msg.topic = topic
        msg.payload = json.dumps(payload).encode("utf-8")
        node._on_message(node.client, None, msg)

    def test_p06_command_ack_dedup_and_validation(self):
        with patch.object(simulator.mqtt, "Client") as factory:
            client = factory.return_value
            client.publish.return_value = Mock(rc=simulator.mqtt.MQTT_ERR_SUCCESS)
            node = self.make_node(deployment_id="dep-test")
            node._on_connect(client, None, None, 0)
            client.publish.reset_mock()

            cmd_topic = "adht/weather/adht_weather_02/command"
            ack_topic = "adht/weather/adht_weather_02/ack"

            # Valid command -> applied ACK
            self._deliver(node, cmd_topic, {
                "request_id": "cmd-1",
                "device_id": "adht_weather_02",
                "deployment_id": "dep-test",
                "cmd": "reset_rain",
                "arg": "",
            })
            self.assertEqual(node.rain_reset_epoch, 1)
            pub_topic, pub_raw = client.publish.call_args.args[0:2]
            self.assertEqual(pub_topic, ack_topic)
            ack = json.loads(pub_raw)
            self.assertEqual(ack["request_id"], "cmd-1")
            self.assertEqual(ack["kind"], "command")
            self.assertEqual(ack["status"], "applied")

            # Duplicate request_id -> replay ACK without re-executing
            client.publish.reset_mock()
            self._deliver(node, cmd_topic, {
                "request_id": "cmd-1",
                "device_id": "adht_weather_02",
                "deployment_id": "dep-test",
                "cmd": "reset_rain",
                "arg": "",
            })
            self.assertEqual(node.rain_reset_epoch, 1)
            ack = json.loads(client.publish.call_args.args[1])
            self.assertEqual(ack["status"], "applied")

            # Expired command -> failed ACK
            client.publish.reset_mock()
            self._deliver(node, cmd_topic, {
                "request_id": "cmd-exp",
                "deployment_id": "dep-test",
                "cmd": "buzzer",
                "expires_at": "2020-01-01T00:00:00Z",
            })
            ack = json.loads(client.publish.call_args.args[1])
            self.assertEqual(ack["status"], "failed")
            self.assertEqual(ack["error_code"], "expired")

            # Unknown command -> rejected ACK
            client.publish.reset_mock()
            self._deliver(node, cmd_topic, {
                "request_id": "cmd-bad",
                "deployment_id": "dep-test",
                "cmd": "self_destruct",
            })
            ack = json.loads(client.publish.call_args.args[1])
            self.assertEqual(ack["status"], "rejected")
            self.assertEqual(ack["error_code"], "unknown_command")

    def test_p06_config_version_conflict_and_ack(self):
        with patch.object(simulator.mqtt, "Client") as factory:
            client = factory.return_value
            client.publish.return_value = Mock(rc=simulator.mqtt.MQTT_ERR_SUCCESS)
            node = self.make_node(deployment_id="dep-test")
            node._on_connect(client, None, None, 0)
            client.publish.reset_mock()

            cfg_topic = "adht/weather/adht_weather_02/config"

            # Apply v1
            self._deliver(node, cfg_topic, {
                "request_id": "cfg-1",
                "deployment_id": "dep-test",
                "version": 1,
                "temp_max": 40.0,
            })
            self.assertEqual(node.config_version, 1)
            self.assertEqual(node.sys_config["temp_max"], 40.0)
            ack = json.loads(client.publish.call_args.args[1])
            self.assertEqual(ack["kind"], "config")
            self.assertEqual(ack["status"], "applied")
            self.assertEqual(ack["version"], 1)

            # Same version + same content -> idempotent applied ACK
            client.publish.reset_mock()
            self._deliver(node, cfg_topic, {
                "request_id": "cfg-1-dup",
                "deployment_id": "dep-test",
                "version": 1,
                "temp_max": 40.0,
            })
            ack = json.loads(client.publish.call_args.args[1])
            self.assertEqual(ack["status"], "applied")
            self.assertEqual(ack["version"], 1)

            # Same version + different content -> version_conflict
            client.publish.reset_mock()
            self._deliver(node, cfg_topic, {
                "request_id": "cfg-conflict",
                "deployment_id": "dep-test",
                "version": 1,
                "temp_max": 42.0,
            })
            self.assertEqual(node.sys_config["temp_max"], 40.0)
            ack = json.loads(client.publish.call_args.args[1])
            self.assertEqual(ack["status"], "rejected")
            self.assertEqual(ack["error_code"], "version_conflict")

            # Invalid domain v2 -> rejected
            client.publish.reset_mock()
            self._deliver(node, cfg_topic, {
                "request_id": "cfg-invalid",
                "deployment_id": "dep-test",
                "version": 2,
                "temp_min": 50.0,
                "temp_max": 40.0,
            })
            self.assertEqual(node.config_version, 1)
            ack = json.loads(client.publish.call_args.args[1])
            self.assertEqual(ack["status"], "rejected")
            self.assertEqual(ack["error_code"], "invalid_domain")

    def test_p06_ack_queued_when_disconnected_and_flushed_on_reconnect(self):
        with patch.object(simulator.mqtt, "Client") as factory:
            client = factory.return_value
            client.publish.return_value = Mock(rc=simulator.mqtt.MQTT_ERR_SUCCESS)
            node = self.make_node(deployment_id="dep-test")

            self._deliver(node, "adht/weather/adht_weather_02/command", {
                "request_id": "cmd-offline",
                "deployment_id": "dep-test",
                "cmd": "led",
                "arg": "on",
            })
            self.assertEqual(len(node.pending_acks), 1)
            client.publish.assert_not_called()

            node._on_connect(client, None, None, 0)
            self.assertEqual(len(node.pending_acks), 0)
            ack_calls = [
                c for c in client.publish.call_args_list
                if c.args[0] == "adht/weather/adht_weather_02/ack"
            ]
            self.assertEqual(len(ack_calls), 1)
            self.assertEqual(json.loads(ack_calls[0].args[1])["request_id"], "cmd-offline")

    def test_rain_tip_accumulator_increments_over_ticks(self):
        with patch.object(simulator.mqtt, "Client"):
            node = simulator.SimulatedEsp32Node(
                simulator.VIRTUAL_NODE_PROFILES[1],  # adht_weather_03 (base_rain=32.0)
                "example.invalid", 8883, "test", "test",
            )
            for _ in range(18):  # 90s at ~32 mm/h -> ~0.8 mm -> >= 1 tip (0.6317 mm/tip)
                node._update_physics()
            self.assertGreater(node.rain_tip_counter, 0)
            self.assertGreater(node.rain_total, 0.0)


if __name__ == "__main__":
    unittest.main()
