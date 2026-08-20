using Relo.Core;

namespace Relo.Core.Tests;

/// <summary>
/// Ported case for case from ReloTimerParserTests.swift in the macOS app. The
/// two parsers are meant to accept exactly the same input, so these cases
/// should stay in step with the Swift suite.
/// </summary>
public class TimerParserTests
{
    private static readonly TimeZoneInfo Utc = TimeZoneInfo.Utc;

    [Theory]
    [InlineData("10", 600)]        // bare number takes the default unit
    [InlineData("45s", 45)]
    [InlineData("1.5 hours", 5_400)]
    [InlineData("1h 30m", 5_400)]
    [InlineData("17m 45s", 1_065)]
    [InlineData("25:00", 1_500)]   // mm:ss
    [InlineData(":45", 45)]
    [InlineData("1:02:03", 3_723)] // h:mm:ss
    public void ParsesDurationFormats(string input, double expected)
    {
        var parser = new TimerParser(DefaultTimeUnit.Minutes);

        Assert.Equal(expected, parser.Duration(input));
    }

    [Theory]
    [InlineData(DefaultTimeUnit.Seconds, "2", 2)]
    [InlineData(DefaultTimeUnit.Minutes, "2", 120)]
    [InlineData(DefaultTimeUnit.Hours, "2", 7_200)]
    [InlineData(DefaultTimeUnit.Hours, "2m", 120)] // an explicit unit wins
    public void AppliesDefaultUnitOnlyWhenUnitIsMissing(
        DefaultTimeUnit unit,
        string input,
        double expected)
    {
        Assert.Equal(expected, new TimerParser(unit).Duration(input));
    }

    [Theory]
    [InlineData("later")]
    [InlineData("10 elephants")]
    [InlineData("1:60")]  // 60 seconds is not a valid mm:ss second field
    [InlineData("0")]
    [InlineData("")]
    [InlineData(null)]
    public void ReturnsZeroForInvalidDurations(string? input)
    {
        Assert.Equal(0, new TimerParser(DefaultTimeUnit.Minutes).Duration(input));
    }

    [Theory]
    [InlineData("6:15pm", 4_500)]
    [InlineData("615p", 4_500)]     // compact form, no colon
    [InlineData("6:15 am", 47_700)] // already passed today, so rolls over
    [InlineData("midnight", 25_200)]
    [InlineData("noon", 68_400)]
    public void ParsesTimesOfDayAndRollsOverToTheNextDay(string input, double expected)
    {
        var parser = new TimerParser(DefaultTimeUnit.Minutes, Utc);
        var now = new DateTimeOffset(2026, 7, 17, 17, 0, 0, TimeSpan.Zero);

        Assert.Equal(expected, parser.TimeOfDayInterval(input, now));
    }

    [Theory]
    [InlineData("25:00pm")]
    [InlineData("sometime")]
    [InlineData("18:00")]   // bare colon times stay durations, never 24h clock
    [InlineData("")]
    [InlineData(null)]
    public void ReturnsNullForInvalidTimesOfDay(string? input)
    {
        var parser = new TimerParser(DefaultTimeUnit.Minutes, Utc);
        var now = new DateTimeOffset(2026, 7, 17, 17, 0, 0, TimeSpan.Zero);

        Assert.Null(parser.TimeOfDayInterval(input, now));
    }

    [Fact]
    public void TreatsColonTimesAsDurationsNotClockTimes()
    {
        var parser = new TimerParser(DefaultTimeUnit.Minutes);

        // 18:00 is eighteen minutes, not six in the evening.
        Assert.Equal(1_080, parser.Duration("18:00"));
    }

    [Fact]
    public void TakesTheNextSmallerUnitForABareTrailingNumber()
    {
        var parser = new TimerParser(DefaultTimeUnit.Minutes);

        Assert.Equal(5_400, parser.Duration("1h 30"));   // 30 becomes minutes
        Assert.Equal(1_065, parser.Duration("17m 45"));  // 45 becomes seconds
    }
}
