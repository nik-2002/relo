using System.Globalization;

namespace Relo.Core;

/// <summary>
/// Parses the natural-language timer input Relo accepts: plain durations
/// ("45s", "1.5 hours", "1h 30m"), colon durations ("25:00", "1:02:03"), and
/// times of day ("6:15pm", "615p", "noon").
///
/// This is a port of ReloTimerParser.swift and is kept behaviourally identical
/// to it — the macOS test suite is the specification, and TimerParserTests
/// mirrors it case for case.
/// </summary>
public sealed class TimerParser
{
    private enum ParsedUnit
    {
        Hour,
        Minute,
        Second,
    }

    private readonly DefaultTimeUnit _defaultUnit;
    private readonly TimeZoneInfo _timeZone;

    public TimerParser(DefaultTimeUnit defaultUnit, TimeZoneInfo? timeZone = null)
    {
        _defaultUnit = defaultUnit;
        _timeZone = timeZone ?? TimeZoneInfo.Local;
    }

    /// <summary>
    /// Seconds represented by <paramref name="input"/>, or 0 when it is not a
    /// duration this parser recognises.
    /// </summary>
    public double Duration(string? input)
    {
        var trimmed = (input ?? string.Empty).Trim().ToLowerInvariant();
        if (trimmed.Length == 0)
        {
            return 0;
        }

        if (ColonDuration(trimmed) is { } colon)
        {
            return colon;
        }

        if (CompositeDuration(trimmed) is { } composite)
        {
            return composite;
        }

        var numberLength = 0;
        while (numberLength < trimmed.Length &&
               (char.IsAsciiDigit(trimmed[numberLength]) || trimmed[numberLength] == '.'))
        {
            numberLength++;
        }

        var numberPart = trimmed[..numberLength];
        var unitPart = trimmed[numberLength..].Trim();

        if (!double.TryParse(numberPart, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) ||
            value <= 0)
        {
            return 0;
        }

        double multiplier;
        if (unitPart.Length == 0)
        {
            multiplier = _defaultUnit.Multiplier();
        }
        else if (Unit(unitPart) is { } parsedUnit)
        {
            multiplier = Multiplier(parsedUnit);
        }
        else
        {
            return 0;
        }

        return Math.Max(0, value * multiplier);
    }

    /// <summary>
    /// Seconds from <paramref name="now"/> until the next occurrence of a time
    /// of day, or null when the input is not a time of day. Rolls to tomorrow
    /// when the time has already passed today.
    /// </summary>
    public double? TimeOfDayInterval(string? input, DateTimeOffset? now = null)
    {
        var reference = now ?? DateTimeOffset.Now;
        var compact = (input ?? string.Empty)
            .Trim()
            .ToLowerInvariant()
            .Replace(" ", string.Empty)
            .Replace(".", string.Empty);

        if (compact == "noon")
        {
            return IntervalUntil(12, 0, reference);
        }

        if (compact == "midnight")
        {
            return IntervalUntil(0, 0, reference);
        }

        if (compact.EndsWith('a'))
        {
            compact = compact[..^1] + "am";
        }
        else if (compact.EndsWith('p'))
        {
            compact = compact[..^1] + "pm";
        }

        // A time of day must carry an am/pm marker. Bare colon times like
        // "18:00" or "6:15" are deliberately durations, so there is no room
        // for an unambiguous 24-hour syntax here.
        if (!compact.Contains("am") && !compact.Contains("pm"))
        {
            return null;
        }

        if (!compact.Contains(':'))
        {
            var suffix = compact[^2..];
            var prefix = compact[..^2];
            if ((suffix == "am" || suffix == "pm") &&
                prefix.Length >= 3 &&
                prefix.All(char.IsAsciiDigit))
            {
                compact = $"{prefix[..^2]}:{prefix[^2..]}{suffix}";
            }
        }

        // Uppercased because the invariant culture's designators are AM/PM.
        var candidate = compact.ToUpperInvariant();
        string[] formats = ["h:mmtt", "htt"];

        foreach (var format in formats)
        {
            if (!DateTime.TryParseExact(
                    candidate,
                    format,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.None,
                    out var parsed))
            {
                continue;
            }

            if (IntervalUntil(parsed.Hour, parsed.Minute, reference) is { } interval)
            {
                return interval;
            }
        }

        return null;
    }

    /// <summary>
    /// "1h 30m", "17m 45s", and the shorthand "1h 30" where a bare trailing
    /// number takes the next smaller unit.
    /// </summary>
    private double? CompositeDuration(string input)
    {
        var cleaned = input.Replace(",", string.Empty);
        var index = 0;
        double total = 0;
        ParsedUnit? lastUnit = null;

        while (index < cleaned.Length)
        {
            while (index < cleaned.Length && char.IsWhiteSpace(cleaned[index]))
            {
                index++;
            }

            if (index >= cleaned.Length)
            {
                break;
            }

            var numberStart = index;
            while (index < cleaned.Length &&
                   (char.IsAsciiDigit(cleaned[index]) || cleaned[index] == '.'))
            {
                index++;
            }

            var numberText = cleaned[numberStart..index];
            if (!double.TryParse(numberText, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) ||
                value <= 0)
            {
                return null;
            }

            while (index < cleaned.Length && char.IsWhiteSpace(cleaned[index]))
            {
                index++;
            }

            var unitStart = index;
            while (index < cleaned.Length && char.IsAsciiLetter(cleaned[index]))
            {
                index++;
            }

            var unitToken = cleaned[unitStart..index];
            if (unitToken.Length > 0)
            {
                if (Unit(unitToken) is not { } parsedUnit)
                {
                    return null;
                }

                total += value * Multiplier(parsedUnit);
                lastUnit = parsedUnit;
            }
            else
            {
                if (lastUnit is not { } currentUnit || NextSmallerUnit(currentUnit) is not { } nextUnit)
                {
                    return null;
                }

                total += value * Multiplier(nextUnit);
                lastUnit = nextUnit;
            }
        }

        return total > 0 ? total : null;
    }

    /// <summary>"25:00" as mm:ss, ":45" as seconds, "1:02:03" as h:mm:ss.</summary>
    private static double? ColonDuration(string input)
    {
        if (!input.Contains(':'))
        {
            return null;
        }

        var compact = input.Replace(" ", string.Empty);
        if (compact.Contains("am") || compact.Contains("pm"))
        {
            return null;
        }

        var parts = compact.Split(':');
        if (parts.Length is not (2 or 3))
        {
            return null;
        }

        int first;
        if (parts[0].Length == 0 && compact.StartsWith(':'))
        {
            first = 0;
        }
        else if (!int.TryParse(parts[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out first))
        {
            return null;
        }

        if (!int.TryParse(parts[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out var second) ||
            first < 0 || second < 0)
        {
            return null;
        }

        if (parts.Length == 2)
        {
            return second < 60 ? first * 60 + second : null;
        }

        if (!int.TryParse(parts[2], NumberStyles.Integer, CultureInfo.InvariantCulture, out var third) ||
            third < 0 || second >= 60 || third >= 60)
        {
            return null;
        }

        return first * 3600 + second * 60 + third;
    }

    private static double Multiplier(ParsedUnit unit) => unit switch
    {
        ParsedUnit.Hour => 3600,
        ParsedUnit.Minute => 60,
        ParsedUnit.Second => 1,
        _ => 0,
    };

    private static ParsedUnit? Unit(string token) => token switch
    {
        "m" or "min" or "mins" or "minute" or "minutes" => ParsedUnit.Minute,
        "s" or "sec" or "secs" or "second" or "seconds" => ParsedUnit.Second,
        "h" or "hr" or "hrs" or "hour" or "hours" => ParsedUnit.Hour,
        _ => null,
    };

    private static ParsedUnit? NextSmallerUnit(ParsedUnit unit) => unit switch
    {
        ParsedUnit.Hour => ParsedUnit.Minute,
        ParsedUnit.Minute => ParsedUnit.Second,
        _ => null,
    };

    private double? IntervalUntil(int hour, int minute, DateTimeOffset now)
    {
        var local = TimeZoneInfo.ConvertTime(now, _timeZone);
        var target = new DateTimeOffset(
            local.Year,
            local.Month,
            local.Day,
            hour,
            minute,
            0,
            local.Offset);

        if (target <= local)
        {
            target = target.AddDays(1);
        }

        var interval = (target - local).TotalSeconds;
        return interval > 0 ? interval : null;
    }
}
