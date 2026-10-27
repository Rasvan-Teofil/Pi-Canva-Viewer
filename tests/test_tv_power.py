import datetime
import unittest

from modules.tv_power import apply_schedule_update, scheduled_power_state


class ScheduleTests(unittest.TestCase):
    def test_daytime_window_respects_active_days(self) -> None:
        schedule = {"enabled": True, "on_time": "08:00", "off_time": "22:30", "active_days": [0, 1, 2, 3, 4]}
        self.assertEqual(scheduled_power_state(datetime.datetime(2026, 10, 26, 9, 0), schedule), "on")
        self.assertEqual(scheduled_power_state(datetime.datetime(2026, 10, 25, 9, 0), schedule), "standby")

    def test_overnight_window_uses_start_day(self) -> None:
        schedule = {"enabled": True, "on_time": "18:00", "off_time": "02:00", "active_days": [0]}
        self.assertEqual(scheduled_power_state(datetime.datetime(2026, 10, 26, 19, 0), schedule), "on")
        self.assertEqual(scheduled_power_state(datetime.datetime(2026, 10, 27, 1, 0), schedule), "on")
        self.assertEqual(scheduled_power_state(datetime.datetime(2026, 10, 27, 3, 0), schedule), "standby")

    def test_invalid_schedule_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            apply_schedule_update({"schedule": {}}, {"on_time": "08:00", "active_days": []})


if __name__ == "__main__":
    unittest.main()
