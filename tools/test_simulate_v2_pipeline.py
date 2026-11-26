import json
import unittest
from simulate_v2_pipeline import build_minute_log, generate_test_scenarios


class TestSimulateV2Pipeline(unittest.TestCase):
    def test_valid_minute_log_fields(self):
        log = build_minute_log(device_id="sim-01", window_sequence=7, tip_count_start=5, tip_count_end=8)
        self.assertEqual(log["schema_version"], 2)
        self.assertEqual(log["type"], "minute_log")
        self.assertEqual(log["window_sequence"], 7)
        self.assertEqual(log["rain"]["tip_count_start"], 5)
        self.assertEqual(log["rain"]["tip_count_end"], 8)
        self.assertEqual(log["clock_quality"], "synchronized")

    def test_deterministic_scenarios(self):
        scenarios = {s["name"]: s for s in generate_test_scenarios("sim-02")}
        self.assertEqual(scenarios["valid"]["payload"], scenarios["duplicate"]["payload"])
        self.assertNotEqual(
            scenarios["valid"]["payload"]["metrics"]["temperature"]["sum"],
            scenarios["conflict"]["payload"]["metrics"]["temperature"]["sum"],
        )
        self.assertEqual(scenarios["unsynchronized"]["payload"]["clock_quality"], "unsynchronized")
        self.assertGreater(len(json.dumps(scenarios["oversized"]["payload"])), 8192)
        self.assertLess(
            scenarios["counter_decrease"]["payload"]["rain"]["tip_count_end"],
            scenarios["counter_decrease"]["payload"]["rain"]["tip_count_start"],
        )


if __name__ == "__main__":
    unittest.main()
