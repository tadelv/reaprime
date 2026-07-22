#!/usr/bin/env python3

import unittest
from datetime import datetime, timedelta, timezone

import analyze_weight_flow


class AnalyzeWeightFlowTest(unittest.TestCase):
    def test_metrics_use_the_longest_active_run(self):
        start = datetime(2026, 7, 22, tzinfo=timezone.utc)
        flows = [0.0, 1.0, 1.5, 0.0, 2.0, 2.5, 3.5, 3.0]
        samples = [
            {
                "timestamp": start + timedelta(milliseconds=index * 250),
                "weight": float(index),
                "flow": flow,
            }
            for index, flow in enumerate(flows)
        ]

        result = analyze_weight_flow.metrics(samples)

        self.assertEqual(result["samples"], 8)
        self.assertEqual(result["active_samples"], 4)
        self.assertAlmostEqual(result["cadence_hz"], 4.0)
        self.assertAlmostEqual(result["mean_abs_delta"], 2 / 3)
        self.assertAlmostEqual(result["tail_mean_abs_delta"], 2 / 3)
        self.assertAlmostEqual(result["p95_abs_delta"], 1.0)
        self.assertAlmostEqual(result["mean_abs_second_delta"], 1.0)


if __name__ == "__main__":
    unittest.main()
