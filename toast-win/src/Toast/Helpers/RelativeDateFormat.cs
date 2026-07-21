namespace Toast.Helpers;

internal static class RelativeDateFormat
{
    public static string Label(DateTimeOffset date, string prefix)
    {
        var interval = DateTimeOffset.Now - date;
        if (interval.TotalSeconds < 60)
        {
            return $"{prefix} just now";
        }

        if (interval.TotalHours < 1)
        {
            var minutes = Math.Max(1, (int)interval.TotalMinutes);
            return $"{prefix} {minutes}m ago";
        }

        if (interval.TotalDays < 1)
        {
            return $"{prefix} {date.ToLocalTime():t}";
        }

        return $"{prefix} {date.ToLocalTime():g}";
    }

    public static DateTimeOffset? FromUnixMs(double? ms)
    {
        if (ms is null or <= 0)
        {
            return null;
        }

        return DateTimeOffset.FromUnixTimeMilliseconds((long)ms.Value);
    }
}
