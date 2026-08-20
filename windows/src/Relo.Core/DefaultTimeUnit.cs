namespace Relo.Core;

/// <summary>
/// The unit applied to a bare number, when the user types "10" with no unit.
/// Mirrors DefaultTimeUnit in the macOS app.
/// </summary>
public enum DefaultTimeUnit
{
    Seconds,
    Minutes,
    Hours,
}

public static class DefaultTimeUnitExtensions
{
    public const DefaultTimeUnit Default = DefaultTimeUnit.Minutes;

    public static double Multiplier(this DefaultTimeUnit unit) => unit switch
    {
        DefaultTimeUnit.Seconds => 1,
        DefaultTimeUnit.Minutes => 60,
        DefaultTimeUnit.Hours => 3600,
        _ => 60,
    };

    public static string DisplayName(this DefaultTimeUnit unit) => unit switch
    {
        DefaultTimeUnit.Seconds => "Seconds",
        DefaultTimeUnit.Minutes => "Minutes",
        DefaultTimeUnit.Hours => "Hours",
        _ => "Minutes",
    };
}
