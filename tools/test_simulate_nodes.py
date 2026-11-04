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


if __name__ == "__main__":
    unittest.main()
