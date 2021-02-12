using System.Threading;
using System.Diagnostics;
using System;

namespace TrafficGeneratorCsharp
{
    public static class StopwatchExtensions
    {
        public static double ElapsedMilliseconds(this Stopwatch stopwatch)
        {
            if (stopwatch == null)
                throw new ArgumentException("Stopwatch passed cannot be null!");

            return 1000 * stopwatch.ElapsedTicks / (double)Stopwatch.Frequency;
        }

        public static double ElapsedMicroseconds(this Stopwatch stopwatch)
        {
            if (stopwatch == null)
                throw new ArgumentException("Stopwatch passed cannot be null!");

            return 1e6 * stopwatch.ElapsedTicks / (double)Stopwatch.Frequency;
        }

        public static double ElapsedNanoseconds(this Stopwatch stopwatch)
        {
            if (stopwatch == null)
                throw new ArgumentException("Stopwatch passed cannot be null!");

            return 1e9 * stopwatch.ElapsedTicks / (double)Stopwatch.Frequency;
        }
    }
}