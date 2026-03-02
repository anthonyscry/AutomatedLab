using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using OpenCodeLab.Models;
using OpenCodeLab.Services;

namespace OpenCodeLab.ViewModels;

/// <summary>
/// ViewModel for the Documentation Hub view
/// </summary>
public class DocumentationHubViewModel : ObservableObject
{
    private readonly DocumentationIndexService _docService = new();
    private readonly KnowledgeHandoverService _handoverService = new();

    private string _searchQuery = string.Empty;
    private bool _isLoading;
    private string _statusMessage = "Ready";
    private DocumentationDocument? _selectedDocument;
    private DocumentationSearchResult? _selectedSearchResult;
    private string _documentContent = string.Empty;

    public ObservableCollection<DocumentationSearchResult> SearchResults { get; } = new();
    public ObservableCollection<DocumentationDocument> RecentDocuments { get; } = new();
    public ObservableCollection<DecisionRecord> DecisionRecords { get; } = new();
    public ObservableCollection<RunbookDocument> Runbooks { get; } = new();

    public AsyncCommand SearchCommand { get; }
    public AsyncCommand LoadCommand { get; }
    public AsyncCommand RefreshIndexCommand { get; }
    public AsyncCommand OpenDocumentCommand { get; }
    public AsyncCommand CreateDecisionRecordCommand { get; }
    public AsyncCommand GenerateOnboardingGuideCommand { get; }
    public AsyncCommand ExportCommand { get; }

    public string SearchQuery
    {
        get => _searchQuery;
        set { _searchQuery = value; OnPropertyChanged(); }
    }

    public bool IsLoading
    {
        get => _isLoading;
        set { _isLoading = value; OnPropertyChanged(); RefreshCommands(); }
    }

    public string StatusMessage
    {
        get => _statusMessage;
        set { _statusMessage = value; OnPropertyChanged(); }
    }

    public DocumentationDocument? SelectedDocument
    {
        get => _selectedDocument;
        set
        {
            _selectedDocument = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(HasSelectedDocument));
            if (value != null)
                _ = LoadDocumentContentAsync(value.Id);
        }
    }

    public DocumentationSearchResult? SelectedSearchResult
    {
        get => _selectedSearchResult;
        set
        {
            _selectedSearchResult = value;
            OnPropertyChanged();
            if (value != null)
                _ = LoadDocumentContentAsync(value.DocumentId);
        }
    }

    public string DocumentContent
    {
        get => _documentContent;
        set { _documentContent = value; OnPropertyChanged(); }
    }

    public bool HasSelectedDocument => SelectedDocument != null;

    // New decision record fields
    private string _newDecisionTitle = string.Empty;
    private string _newDecisionContext = string.Empty;
    private string _newDecisionDecision = string.Empty;
    private string _newDecisionConsequences = string.Empty;
    private string _newDecisionLabName = string.Empty;

    public string NewDecisionTitle
    {
        get => _newDecisionTitle;
        set { _newDecisionTitle = value; OnPropertyChanged(); }
    }

    public string NewDecisionContext
    {
        get => _newDecisionContext;
        set { _newDecisionContext = value; OnPropertyChanged(); }
    }

    public string NewDecisionDecision
    {
        get => _newDecisionDecision;
        set { _newDecisionDecision = value; OnPropertyChanged(); }
    }

    public string NewDecisionConsequences
    {
        get => _newDecisionConsequences;
        set { _newDecisionConsequences = value; OnPropertyChanged(); }
    }

    public string NewDecisionLabName
    {
        get => _newDecisionLabName;
        set { _newDecisionLabName = value; OnPropertyChanged(); }
    }

    public DocumentationHubViewModel()
    {
        LoadCommand = new AsyncCommand(LoadAsync, () => !IsLoading);
        SearchCommand = new AsyncCommand(SearchAsync, () => !IsLoading);
        RefreshIndexCommand = new AsyncCommand(RefreshIndexAsync, () => !IsLoading);
        OpenDocumentCommand = new AsyncCommand(OpenDocumentAsync, () => SelectedSearchResult != null);
        CreateDecisionRecordCommand = new AsyncCommand(CreateDecisionRecordAsync, () => !IsLoading && !string.IsNullOrWhiteSpace(NewDecisionTitle));
        GenerateOnboardingGuideCommand = new AsyncCommand(GenerateOnboardingGuideAsync, () => !IsLoading && !string.IsNullOrWhiteSpace(NewDecisionLabName));
        ExportCommand = new AsyncCommand(ExportAsync, () => !string.IsNullOrWhiteSpace(DocumentContent));
    }

    public async Task LoadAsync()
    {
        IsLoading = true;
        StatusMessage = "Loading documentation...";

        try
        {
            // Load decision records
            var decisions = await _handoverService.GetDecisionRecordsAsync();
            DecisionRecords.Clear();
            foreach (var decision in decisions.OrderByDescending(d => d.CreatedAt))
                DecisionRecords.Add(decision);

            // Initial search (shows all)
            await SearchAsync();

            StatusMessage = $"Loaded {DecisionRecords.Count} decision records, {SearchResults.Count} documents";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Error loading: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task SearchAsync()
    {
        IsLoading = true;
        StatusMessage = "Searching...";

        try
        {
            var results = await _docService.SearchAsync(SearchQuery, 50);
            SearchResults.Clear();
            foreach (var result in results)
                SearchResults.Add(result);

            StatusMessage = $"Found {SearchResults.Count} document(s)";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Search error: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task RefreshIndexAsync()
    {
        IsLoading = true;
        StatusMessage = "Reindexing documentation...";

        try
        {
            await _docService.IndexAllAsync(msg => StatusMessage = msg);
            await SearchAsync();
        }
        catch (Exception ex)
        {
            StatusMessage = $"Index error: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task LoadDocumentContentAsync(string documentId)
    {
        try
        {
            var doc = await _docService.LoadDocumentAsync(documentId);
            if (doc != null)
            {
                SelectedDocument = doc;
                DocumentContent = doc.Content;
                StatusMessage = $"Viewing: {doc.Title}";
            }
        }
        catch (Exception ex)
        {
            StatusMessage = $"Error loading document: {ex.Message}";
        }
    }

    private async Task OpenDocumentAsync()
    {
        if (SelectedSearchResult == null) return;
        await LoadDocumentContentAsync(SelectedSearchResult.DocumentId);
    }

    private async Task CreateDecisionRecordAsync()
    {
        if (string.IsNullOrWhiteSpace(NewDecisionTitle))
            return;

        IsLoading = true;
        StatusMessage = "Creating decision record...";

        try
        {
            var record = await _handoverService.CreateDecisionRecordAsync(
                NewDecisionTitle,
                NewDecisionContext,
                NewDecisionDecision,
                NewDecisionConsequences,
                string.IsNullOrWhiteSpace(NewDecisionLabName) ? null : NewDecisionLabName);

            DecisionRecords.Insert(0, record);

            // Clear form
            NewDecisionTitle = string.Empty;
            NewDecisionContext = string.Empty;
            NewDecisionDecision = string.Empty;
            NewDecisionConsequences = string.Empty;

            StatusMessage = $"Created {record.ShortId}: {record.Title}";
            MessageBox.Show($"Decision record created: {record.ShortId}\n\n{record.Title}", "Decision Record Created", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            StatusMessage = $"Error creating decision: {ex.Message}";
            MessageBox.Show($"Failed to create decision record:\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task GenerateOnboardingGuideAsync()
    {
        if (string.IsNullOrWhiteSpace(NewDecisionLabName))
            return;

        IsLoading = true;
        StatusMessage = "Generating onboarding guide...";

        try
        {
            var guide = await _handoverService.GenerateOnboardingGuideAsync(NewDecisionLabName);
            DocumentContent = guide.Content;
            StatusMessage = $"Generated onboarding guide for {NewDecisionLabName}";
            MessageBox.Show($"Onboarding guide generated:\n{guide.Content.Length} characters", "Guide Generated", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            StatusMessage = $"Error generating guide: {ex.Message}";
            MessageBox.Show($"Failed to generate guide:\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task ExportAsync()
    {
        if (string.IsNullOrWhiteSpace(DocumentContent))
            return;

        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            FileName = "document-export",
            Filter = "Markdown files (*.md)|*.md|Text files (*.txt)|*.txt",
            DefaultExt = ".md"
        };

        if (dialog.ShowDialog() == true)
        {
            try
            {
                await System.IO.File.WriteAllTextAsync(dialog.FileName, DocumentContent);
                StatusMessage = $"Exported to {dialog.FileName}";
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to export:\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }

    private void RefreshCommands()
    {
        LoadCommand.RaiseCanExecuteChanged();
        SearchCommand.RaiseCanExecuteChanged();
        RefreshIndexCommand.RaiseCanExecuteChanged();
        OpenDocumentCommand.RaiseCanExecuteChanged();
        CreateDecisionRecordCommand.RaiseCanExecuteChanged();
        GenerateOnboardingGuideCommand.RaiseCanExecuteChanged();
        ExportCommand.RaiseCanExecuteChanged();
    }
}
