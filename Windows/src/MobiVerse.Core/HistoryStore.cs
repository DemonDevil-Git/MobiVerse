using System.Text.Json;
using System.Text.Json.Serialization;

namespace MobiVerse.Core;

public sealed class HistoryStore(string? historyPath = null) : IHistoryStore
{
    public string HistoryPath { get; } = historyPath ?? Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "MobiVerse",
        "history.json");

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter() }
    };

    public IReadOnlyList<ConversionTask> Load()
    {
        try
        {
            if (!File.Exists(HistoryPath)) return [];
            var tasks = JsonSerializer.Deserialize<List<ConversionTask>>(File.ReadAllText(HistoryPath), Options) ?? [];
            foreach (var task in tasks)
            {
                if (task.Status is ConversionStatus.CheckingTools or ConversionStatus.Converting or ConversionStatus.Validating)
                {
                    task.Status = ConversionStatus.Failed;
                    task.Progress = 1;
                    task.StatusMessage = "Interrupted before completion";
                    task.CompletedAt ??= DateTimeOffset.Now;
                }
                else if (task.Status == ConversionStatus.Queued)
                {
                    task.Progress = 0;
                    task.StatusMessage = "Waiting";
                }
            }
            return tasks;
        }
        catch (JsonException) { return []; }
        catch (IOException) { return []; }
        catch (UnauthorizedAccessException) { return []; }
    }

    public void Save(IReadOnlyList<ConversionTask> tasks)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(HistoryPath)!);
            var temporaryPath = HistoryPath + ".tmp";
            File.WriteAllText(temporaryPath, JsonSerializer.Serialize(tasks, Options));
            File.Move(temporaryPath, HistoryPath, true);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}

public sealed class ReadingPositionStore(string? storagePath = null)
{
    private readonly string _storagePath = storagePath ?? Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "MobiVerse",
        "preview-reading-positions.json");

    public int Get(string epubPath)
    {
        var positions = Load();
        return positions.TryGetValue(Key(epubPath), out var value) ? Math.Max(0, value) : 0;
    }

    public void Save(string epubPath, int pageIndex)
    {
        try
        {
            var positions = Load();
            positions[Key(epubPath)] = Math.Max(0, pageIndex);
            Directory.CreateDirectory(Path.GetDirectoryName(_storagePath)!);
            File.WriteAllText(_storagePath, JsonSerializer.Serialize(positions));
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private Dictionary<string, int> Load()
    {
        try
        {
            return File.Exists(_storagePath)
                ? JsonSerializer.Deserialize<Dictionary<string, int>>(File.ReadAllText(_storagePath)) ?? new(StringComparer.OrdinalIgnoreCase)
                : new(StringComparer.OrdinalIgnoreCase);
        }
        catch { return new(StringComparer.OrdinalIgnoreCase); }
    }

    private static string Key(string path) => Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar).ToUpperInvariant();
}
