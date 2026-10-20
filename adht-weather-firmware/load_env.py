# load_env.py - PlatformIO Pre-build script to inject .env variables
Import("env")
import os

# Check for .env in current project directory, or parent monorepo directory
env_path = os.path.join(env.get("PROJECT_DIR"), ".env")
if not os.path.exists(env_path):
    env_path = os.path.join(env.get("PROJECT_DIR"), "..", ".env")

if os.path.exists(env_path):
    print(f"[ENV] Found .env file at: {env_path}")
    with open(env_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            key = key.strip()
            val = val.strip().strip("'\"")
            
            # Numeric types (e.g. PORT)
            if key == "MQTT_BROKER_PORT" and val.isdigit():
                env.Append(CPPDEFINES=[(key, int(val))])
            else:
                env.Append(CPPDEFINES=[(key, env.StringifyMacro(val))])
    print("[ENV] Environment variables successfully injected into build!")
else:
    print("[ENV] Notice: No .env file found. Using default values from config.h")

