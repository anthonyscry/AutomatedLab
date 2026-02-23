using System.Reflection;

namespace OpenCodeLab;

public static class AppVersion
{
    public static string Display { get; } = ResolveDisplayVersion();

    private static string ResolveDisplayVersion()
    {
        var assembly = Assembly.GetExecutingAssembly();
        var informationalVersion = assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion;

        if (!string.IsNullOrWhiteSpace(informationalVersion))
        {
            var metadataSeparatorIndex = informationalVersion.IndexOf('+');
            return metadataSeparatorIndex > 0
                ? informationalVersion[..metadataSeparatorIndex]
                : informationalVersion;
        }

        var version = assembly.GetName().Version;
        return version is null
            ? "Unknown"
            : $"{version.Major}.{version.Minor}.{version.Build}";
    }
}
