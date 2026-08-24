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
        return GetPosition(epubPath, legacyValueIsSection: false).PageIndex;
    }

    public void Save(string epubPath, int pageIndex)
    {
        SavePosition(epubPath, new PreviewReadingPosition(0, pageIndex));
    }

    public PreviewReadingPosition GetPosition(string epubPath, bool legacyValueIsSection)
    {
        var positions = Load();
        if (!positions.TryGetValue(Key(epubPath), out var value)) return new(0, 0);
        if (value.SectionIndex is not null && value.PageIndex is not null)
            return new(value.SectionIndex.Value, value.PageIndex.Value);
        var legacy = Math.Max(0, value.LegacyIndex ?? 0);
        return legacyValueIsSection ? new(legacy, 0) : new(0, legacy);
    }

    public void SavePosition(string epubPath, PreviewReadingPosition position)
    {
        try
        {
            var positions = Load();
            positions[Key(epubPath)] = new(position.SectionIndex, position.PageIndex, null);
            Directory.CreateDirectory(Path.GetDirectoryName(_storagePath)!);
            File.WriteAllText(_storagePath, JsonSerializer.Serialize(positions));
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private Dictionary<string, StoredReadingPosition> Load()
    {
        try
        {
            if (!File.Exists(_storagePath)) return new(StringComparer.OrdinalIgnoreCase);
            var json = File.ReadAllText(_storagePath);
            try
            {
                return JsonSerializer.Deserialize<Dictionary<string, StoredReadingPosition>>(json) ?? new(StringComparer.OrdinalIgnoreCase);
            }
            catch (JsonException)
            {
                var legacy = JsonSerializer.Deserialize<Dictionary<string, int>>(json) ?? new(StringComparer.OrdinalIgnoreCase);
                return legacy.ToDictionary(pair => pair.Key, pair => new StoredReadingPosition(null, null, Math.Max(0, pair.Value)), StringComparer.OrdinalIgnoreCase);
            }
        }
        catch { return new(StringComparer.OrdinalIgnoreCase); }
    }

    private static string Key(string path) => Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar).ToUpperInvariant();

    private sealed record StoredReadingPosition(int? SectionIndex, int? PageIndex, int? LegacyIndex);
}
