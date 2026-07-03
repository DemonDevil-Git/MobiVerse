using System.Diagnostics;
using System.Text;

namespace MobiVerse.Core;

public sealed class ProcessRunner : IProcessRunner
{
    public async Task<ProcessRunResult> RunAsync(
        string executablePath,
        IReadOnlyList<string> arguments,
        string? workingDirectory = null,
        CancellationToken cancellationToken = default)
    {
        var extension = Path.GetExtension(executablePath);
        var isBatch = extension.Equals(".bat", StringComparison.OrdinalIgnoreCase) ||
                      extension.Equals(".cmd", StringComparison.OrdinalIgnoreCase);
        var actualExecutable = isBatch ? Environment.GetEnvironmentVariable("COMSPEC") ?? "cmd.exe" : executablePath;
        var startInfo = new ProcessStartInfo(actualExecutable)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = workingDirectory ?? Path.GetDirectoryName(executablePath) ?? Environment.CurrentDirectory
        };
        if (isBatch)
        {
            startInfo.ArgumentList.Add("/d");
            startInfo.ArgumentList.Add("/c");
            startInfo.ArgumentList.Add(executablePath);
        }
        foreach (var argument in arguments) startInfo.ArgumentList.Add(argument);

        using var process = new Process { StartInfo = startInfo };
        var output = new StringBuilder();
        process.OutputDataReceived += (_, eventArgs) => { if (eventArgs.Data is not null) output.AppendLine(eventArgs.Data); };
        process.ErrorDataReceived += (_, eventArgs) => { if (eventArgs.Data is not null) output.AppendLine(eventArgs.Data); };
        if (!process.Start()) throw new InvalidOperationException($"Could not start {executablePath}.");
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        return new ProcessRunResult(process.ExitCode, output.ToString());
    }
}
