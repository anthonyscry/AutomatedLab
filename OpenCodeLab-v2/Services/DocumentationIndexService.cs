using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

/// <summary>
/// Service for indexing and searching documentation
/// </summary>
public class DocumentationIndexService
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private const string IndexFile = "doc-index.json";
    private List<DocumentationIndexEntry> _index = new();

    /// <summary>
    /// Index all documentation in the system
    /// </summary>
    public async Task IndexAllAsync(Action<string>? log = null, CancellationToken ct = default)
    {
        log?.Invoke("Starting documentation indexing...");
        _index.Clear();

        // Index built-in docs from docs/ folder
        var docsDir = Path.Combine(AppContext.BaseDirectory, "docs");
        if (Directory.Exists(docsDir))
        {
            await IndexDirectoryAsync(docsDir, DocumentationSourceType.BuiltIn, ct);
        }

        // Index docs from LabSources
        var labSourcesDocs = @"C:\LabSources\Docs";
        if (Directory.Exists(labSourcesDocs))
        {
            await IndexDirectoryAsync(labSourcesDocs, DocumentationSourceType.UserCreated, ct);
        }

        // Index lab-specific docs
        var labConfigDir = @"C:\LabSources\LabConfig";
        if (Directory.Exists(labConfigDir))
        {
            foreach (var labDir in Directory.GetDirectories(labConfigDir))
            {
                var docsPath = Path.Combine(labDir, "docs");
                if (Directory.Exists(docsPath))
                {
                    var labName = Path.GetFileName(labDir);
                    await IndexDirectoryAsync(docsPath, DocumentationSourceType.Generated, ct, labName);
                }
            }
        }

        // Save index
        await SaveIndexAsync(ct);
        log?.Invoke($"Indexing complete. {_index.Count} documents indexed.");
    }

    /// <summary>
    /// Search documentation
    /// </summary>
    public async Task<List<DocumentationSearchResult>> SearchAsync(string query, int maxResults = 20, CancellationToken ct = default)
    {
        await LoadIndexAsync(ct);

        if (string.IsNullOrWhiteSpace(query))
            return _index.Take(maxResults).Select(e => new DocumentationSearchResult
            {
                DocumentId = e.DocumentId,
                Title = e.Title,
                Description = e.Description,
                Category = e.Category,
                CategoryEmoji = GetCategoryEmoji(e.Category),
                SourceType = e.SourceType,
                UpdatedAt = e.UpdatedAt
            }).ToList();

        var queryWords = query.ToLowerInvariant().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var results = new List<DocumentationSearchResult>();

        foreach (var entry in _index)
        {
            var score = CalculateRelevanceScore(entry, queryWords);
            if (score > 0)
            {
                results.Add(new DocumentationSearchResult
                {
                    DocumentId = entry.DocumentId,
                    Title = entry.Title,
                    Description = entry.Description,
                    Category = entry.Category,
                    CategoryEmoji = GetCategoryEmoji(entry.Category),
                    SourceType = entry.SourceType,
                    UpdatedAt = entry.UpdatedAt,
                    RelevanceScore = score
                });
            }
        }

        return results
            .OrderByDescending(r => r.RelevanceScore)
            .ThenByDescending(r => r.UpdatedAt)
            .Take(maxResults)
            .ToList();
    }

    /// <summary>
    /// Get all documents by category
    /// </summary>
    public async Task<List<DocumentationDocument>> GetByCategoryAsync(DocumentationCategory category, CancellationToken ct = default)
    {
        await LoadIndexAsync(ct);
        // This would load actual documents from disk based on index
        return new List<DocumentationDocument>();
    }

    /// <summary>
    /// Load a specific document
    /// </summary>
    public async Task<DocumentationDocument?> LoadDocumentAsync(string documentId, CancellationToken ct = default)
    {
        await LoadIndexAsync(ct);
        var entry = _index.FirstOrDefault(e => e.DocumentId == documentId);
        if (entry == null) return null;

        // Load content from file
        var doc = new DocumentationDocument
        {
            Id = entry.DocumentId,
            Title = entry.Title,
            Description = entry.Description,
            Category = Enum.Parse<DocumentationCategory>(entry.Category),
            SourceType = Enum.Parse<DocumentationSourceType>(entry.SourceType),
            UpdatedAt = entry.UpdatedAt
        };

        // Try to load content
        var contentPath = GetDocumentPath(entry);
        if (File.Exists(contentPath))
        {
            doc.Content = await File.ReadAllTextAsync(contentPath, ct);
            doc.ContentPath = contentPath;
        }

        return doc;
    }

    private async Task IndexDirectoryAsync(string directory, DocumentationSourceType sourceType, CancellationToken ct, string? labName = null)
    {
        foreach (var file in Directory.GetFiles(directory, "*.md", SearchOption.AllDirectories))
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                var content = await File.ReadAllTextAsync(file, ct);
                var entry = CreateIndexEntry(file, content, sourceType, labName);
                if (entry != null)
                    _index.Add(entry);
            }
            catch { }
        }
    }

    private DocumentationIndexEntry CreateIndexEntry(string filePath, string content, DocumentationSourceType sourceType, string? labName)
    {
        var fileName = Path.GetFileNameWithoutExtension(filePath);
        var title = ExtractTitle(content) ?? fileName;

        return new DocumentationIndexEntry
        {
            DocumentId = Guid.NewGuid().ToString("N"),
            Title = title,
            Description = ExtractDescription(content),
            Keywords = ExtractKeywords(content),
            Category = DetermineCategory(filePath, content).ToString(),
            SourceType = sourceType.ToString(),
            UpdatedAt = File.GetLastWriteTimeUtc(filePath)
        };
    }

    private static string? ExtractTitle(string content)
    {
        var firstLine = content.Split('\n').FirstOrDefault(l => l.StartsWith("#"));
        return firstLine?.TrimStart('#').Trim();
    }

    private static string? ExtractDescription(string content)
    {
        var lines = content.Split('\n');
        for (int i = 0; i < Math.Min(lines.Length, 10); i++)
        {
            var line = lines[i].Trim();
            if (!string.IsNullOrWhiteSpace(line) && !line.StartsWith("#"))
                return line.Length > 200 ? line.Substring(0, 200) + "..." : line;
        }
        return null;
    }

    private static List<string> ExtractKeywords(string content)
    {
        var keywords = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var words = content.Split(new[] { ' ', '\n', '\r', '\t' }, StringSplitOptions.RemoveEmptyEntries);

        foreach (var word in words)
        {
            var cleaned = new string(word.Where(char.IsLetterOrDigit).ToArray()).ToLowerInvariant();
            if (cleaned.Length > 3 && !IsStopWord(cleaned))
                keywords.Add(cleaned);
        }

        return keywords.Take(50).ToList();
    }

    private static bool IsStopWord(string word)
    {
        var stopWords = new HashSet<string> { "the", "and", "for", "are", "but", "not", "you", "all", "can", "had", "her", "was", "one", "our", "out", "with", "this", "that", "from", "they", "have", "been", "will" };
        return stopWords.Contains(word);
    }

    private static DocumentationCategory DetermineCategory(string filePath, string content)
    {
        var fileName = Path.GetFileNameWithoutExtension(filePath).ToLowerInvariant();
        var path = filePath.ToLowerInvariant();

        if (path.Contains("architecture")) return DocumentationCategory.Architecture;
        if (path.Contains("troubleshoot")) return DocumentationCategory.Troubleshooting;
        if (path.Contains("runbook")) return DocumentationCategory.Runbook;
        if (path.Contains("decision") || path.Contains("adr")) return DocumentationCategory.DecisionLog;
        if (path.Contains("release") || path.Contains("changelog")) return DocumentationCategory.ReleaseNotes;
        if (path.Contains("api")) return DocumentationCategory.ApiReference;
        if (path.Contains("labconfig")) return DocumentationCategory.LabSpecific;
        if (content.Contains("operation", StringComparison.OrdinalIgnoreCase)) return DocumentationCategory.Operations;

        return DocumentationCategory.UserGuide;
    }

    private static int CalculateRelevanceScore(DocumentationIndexEntry entry, string[] queryWords)
    {
        int score = 0;
        var titleLower = entry.Title.ToLowerInvariant();
        var descLower = entry.Description?.ToLowerInvariant() ?? "";

        foreach (var word in queryWords)
        {
            if (titleLower.Contains(word)) score += 10;
            if (descLower.Contains(word)) score += 5;
            if (entry.Keywords.Any(k => k.Contains(word))) score += 2;
        }

        return score;
    }

    private static string GetCategoryEmoji(string category)
    {
        return Enum.TryParse<DocumentationCategory>(category, out var cat)
            ? new DocumentationDocument { Category = cat }.CategoryEmoji
            : "📄";
    }

    private static string GetDocumentPath(DocumentationIndexEntry entry)
    {
        // This would need to be stored in the entry
        return entry.SourceType == DocumentationSourceType.BuiltIn.ToString()
            ? Path.Combine(AppContext.BaseDirectory, "docs", $"{entry.Title}.md")
            : Path.Combine(@"C:\LabSources\Docs", $"{entry.Title}.md");
    }

    private async Task SaveIndexAsync(CancellationToken ct)
    {
        var indexPath = GetIndexPath();
        Directory.CreateDirectory(Path.GetDirectoryName(indexPath)!);
        var json = JsonSerializer.Serialize(_index, JsonOptions);
        await File.WriteAllTextAsync(indexPath, json, ct);
    }

    private async Task LoadIndexAsync(CancellationToken ct)
    {
        if (_index.Count > 0) return;

        var indexPath = GetIndexPath();
        if (!File.Exists(indexPath))
        {
            await IndexAllAsync(null, ct);
            return;
        }

        var json = await File.ReadAllTextAsync(indexPath, ct);
        var index = JsonSerializer.Deserialize<List<DocumentationIndexEntry>>(json);
        _index = index ?? new List<DocumentationIndexEntry>();
    }

    private static string GetIndexPath()
    {
        return Path.Combine(@"C:\LabSources\LabConfig", "_system", IndexFile);
    }
}
