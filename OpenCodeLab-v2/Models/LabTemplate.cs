using System;
using System.Collections.Generic;

namespace OpenCodeLab.Models;

public class LabTemplate
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Author { get; set; } = string.Empty;
    public string Version { get; set; } = "1.0";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public bool IsBuiltIn { get; set; }
    public string? IconGlyph { get; set; }
    public List<string> Tags { get; set; } = new();
    public LabConfig Config { get; set; } = new();
}
