package main

import (
	"context"
	"encoding/json"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/MichaelKinsy/PiG/ai"
	"github.com/MichaelKinsy/PiG/coding/extension"
)

const webSearchToolName = "web_search"

const webSearchDescription = `Search the public web for current or unknown information: news, facts, prices, releases, people, places, or anything you are unsure about. Returns a direct answer when available, plus titles, URLs, and snippets. After using it, answer in at most three short sentences and cite the source URLs. Do not use it for math, code in the conversation, or information already present in the context.`

const webSearchParameters = `{
  "type": "object",
  "properties": {
    "query": {"type": "string", "description": "The search query, in natural language or keywords."},
    "max_results": {"type": "integer", "minimum": 1, "maximum": 8, "description": "How many results to return. Default 5."}
  },
  "required": ["query"],
  "additionalProperties": false
}`

type searchResult struct {
	Title   string
	URL     string
	Snippet string
}

type searchResponse struct {
	Answer  string
	Results []searchResult
	Source  string
}

type cachedSearch struct {
	at   time.Time
	resp searchResponse
	err  string
}

var (
	searchClient = &http.Client{Timeout: 8 * time.Second}
	searchCache  = struct {
		sync.Mutex
		entries map[string]cachedSearch
	}{entries: make(map[string]cachedSearch)}
	tagPattern = regexp.MustCompile(`<[^>]+>`)
)

func webSearchTool() extension.ToolDefinition {
	active := true
	return extension.ToolDefinition{
		Name:          webSearchToolName,
		Label:         "Web search",
		Description:   webSearchDescription,
		Parameters:    json.RawMessage(webSearchParameters),
		DefaultActive: &active,
		Execute:       executeWebSearch,
	}
}

func executeWebSearch(ctx context.Context, _ string, params json.RawMessage, _ extension.AgentToolUpdateCallback) (extension.AgentToolResult, error) {
	var args struct {
		Query      string `json:"query"`
		MaxResults int    `json:"max_results"`
	}
	if err := json.Unmarshal(params, &args); err != nil {
		return searchError("invalid arguments: " + err.Error()), nil
	}
	query := strings.TrimSpace(args.Query)
	if query == "" {
		return searchError("query is required"), nil
	}
	maxResults := args.MaxResults
	if maxResults <= 0 {
		maxResults = 5
	}
	if maxResults > 8 {
		maxResults = 8
	}

	callCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

	resp, err := searchWeb(callCtx, query, maxResults)
	if err != nil {
		return searchError(err.Error()), nil
	}
	return extension.AgentToolResult{
		Content: []ai.ToolResultMessageContent{ai.TextContent{Text: formatSearch(resp)}},
	}, nil
}

func searchError(message string) extension.AgentToolResult {
	return extension.AgentToolResult{
		IsError: true,
		Content: []ai.ToolResultMessageContent{ai.TextContent{Text: "web_search: " + message}},
	}
}

func formatSearch(resp searchResponse) string {
	var b strings.Builder
	if resp.Answer != "" {
		b.WriteString("Answer: ")
		b.WriteString(resp.Answer)
		b.WriteString("\n\n")
	}
	b.WriteString("Sources")
	if resp.Source != "" {
		b.WriteString(" (")
		b.WriteString(resp.Source)
		b.WriteString(")")
	}
	b.WriteString(":\n")
	for i, result := range resp.Results {
		fmt.Fprintf(&b, "%d. %s\n   %s\n", i+1, result.Title, result.URL)
		if result.Snippet != "" {
			b.WriteString("   ")
			b.WriteString(result.Snippet)
			b.WriteString("\n")
		}
	}
	return strings.TrimRight(b.String(), "\n")
}

func searchWeb(ctx context.Context, query string, maxResults int) (searchResponse, error) {
	key := query + "\x00" + fmt.Sprint(maxResults)
	searchCache.Lock()
	if entry, ok := searchCache.entries[key]; ok && time.Since(entry.at) < 5*time.Minute {
		searchCache.Unlock()
		if entry.err != "" {
			return searchResponse{}, fmt.Errorf("%s", entry.err)
		}
		return entry.resp, nil
	}
	searchCache.Unlock()

	var errs []string
	if key := strings.TrimSpace(os.Getenv("TAVILY_API_KEY")); key != "" {
		if resp, err := tavilySearch(ctx, key, query, maxResults); err == nil && len(resp.Results) > 0 {
			storeSearch(key, query, maxResults, resp, "")
			return resp, nil
		} else if err != nil {
			errs = append(errs, "tavily: "+err.Error())
		}
	}
	if key := strings.TrimSpace(os.Getenv("BRAVE_API_KEY")); key != "" {
		if resp, err := braveSearch(ctx, key, query, maxResults); err == nil && len(resp.Results) > 0 {
			storeSearch("", query, maxResults, resp, "")
			return resp, nil
		} else if err != nil {
			errs = append(errs, "brave: "+err.Error())
		}
	}
	if base := strings.TrimSpace(os.Getenv("ASSISTANT_SEARX_URL")); base != "" {
		if resp, err := searxSearch(ctx, base, query, maxResults); err == nil && len(resp.Results) > 0 {
			storeSearch("", query, maxResults, resp, "")
			return resp, nil
		} else if err != nil {
			errs = append(errs, "searx: "+err.Error())
		}
	}
	if resp, err := wikipediaSearch(ctx, query, maxResults); err == nil && len(resp.Results) > 0 {
		storeSearch("", query, maxResults, resp, "")
		return resp, nil
	} else if err != nil {
		errs = append(errs, "wikipedia: "+err.Error())
	}
	if resp, err := duckDuckGoInstant(ctx, query); err == nil && (resp.Answer != "" || len(resp.Results) > 0) {
		storeSearch("", query, maxResults, resp, "")
		return resp, nil
	} else if err != nil {
		errs = append(errs, "duckduckgo: "+err.Error())
	}

	message := "no results"
	if len(errs) > 0 {
		message += " (" + strings.Join(errs, "; ") + ")"
	}
	message += ". Set TAVILY_API_KEY or BRAVE_API_KEY for general web search, or ASSISTANT_SEARX_URL for a SearXNG instance."
	storeSearch("", query, maxResults, searchResponse{}, message)
	return searchResponse{}, fmt.Errorf("%s", message)
}

func storeSearch(_ string, query string, maxResults int, resp searchResponse, err string) {
	searchCache.Lock()
	searchCache.entries[query+"\x00"+fmt.Sprint(maxResults)] = cachedSearch{at: time.Now(), resp: resp, err: err}
	for k, entry := range searchCache.entries {
		if time.Since(entry.at) > 10*time.Minute {
			delete(searchCache.entries, k)
		}
	}
	searchCache.Unlock()
}

func tavilySearch(ctx context.Context, key, query string, maxResults int) (searchResponse, error) {
	body, err := json.Marshal(map[string]any{
		"query":               query,
		"search_depth":        "basic",
		"include_answer":      true,
		"include_raw_content": false,
		"max_results":         maxResults,
	})
	if err != nil {
		return searchResponse{}, err
	}
	endpoint := envOr("ASSISTANT_TAVILY_URL", "https://api.tavily.com/search")
	var payload struct {
		Answer  string `json:"answer"`
		Results []struct {
			Title   string `json:"title"`
			URL     string `json:"url"`
			Content string `json:"content"`
		} `json:"results"`
	}
	if err := requestJSON(ctx, http.MethodPost, endpoint, "Bearer "+key, body, &payload); err != nil {
		return searchResponse{}, err
	}
	resp := searchResponse{Answer: strings.TrimSpace(payload.Answer), Source: "Tavily"}
	for _, r := range payload.Results {
		resp.Results = append(resp.Results, searchResult{Title: cleanText(r.Title), URL: r.URL, Snippet: cleanText(r.Content)})
	}
	return resp, nil
}

func braveSearch(ctx context.Context, key, query string, maxResults int) (searchResponse, error) {
	endpoint := envOr("ASSISTANT_BRAVE_URL", "https://api.search.brave.com/res/v1/web/search")
	u, err := url.Parse(endpoint)
	if err != nil {
		return searchResponse{}, err
	}
	q := u.Query()
	q.Set("q", query)
	q.Set("count", fmt.Sprint(maxResults))
	u.RawQuery = q.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return searchResponse{}, err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("X-Subscription-Token", key)
	var payload struct {
		Web struct {
			Results []struct {
				Title       string `json:"title"`
				URL         string `json:"url"`
				Description string `json:"description"`
			} `json:"results"`
		} `json:"web"`
	}
	if err := doJSON(req, &payload); err != nil {
		return searchResponse{}, err
	}
	resp := searchResponse{Source: "Brave"}
	for _, r := range payload.Web.Results {
		resp.Results = append(resp.Results, searchResult{Title: cleanText(r.Title), URL: r.URL, Snippet: cleanText(r.Description)})
	}
	return resp, nil
}

func searxSearch(ctx context.Context, base, query string, maxResults int) (searchResponse, error) {
	u, err := url.Parse(strings.TrimRight(base, "/") + "/search")
	if err != nil {
		return searchResponse{}, err
	}
	q := u.Query()
	q.Set("q", query)
	q.Set("format", "json")
	q.Set("categories", "general")
	u.RawQuery = q.Encode()
	var payload struct {
		Results []struct {
			Title   string `json:"title"`
			URL     string `json:"url"`
			Content string `json:"content"`
		} `json:"results"`
	}
	if err := requestJSON(ctx, http.MethodGet, u.String(), "", nil, &payload); err != nil {
		return searchResponse{}, err
	}
	resp := searchResponse{Source: "SearXNG"}
	for _, r := range payload.Results {
		if len(resp.Results) >= maxResults {
			break
		}
		resp.Results = append(resp.Results, searchResult{Title: cleanText(r.Title), URL: r.URL, Snippet: cleanText(r.Content)})
	}
	return resp, nil
}

func wikipediaSearch(ctx context.Context, query string, maxResults int) (searchResponse, error) {
	endpoint := envOr("ASSISTANT_WIKI_URL", "https://en.wikipedia.org/w/rest.php/v1/search/page")
	u, err := url.Parse(endpoint)
	if err != nil {
		return searchResponse{}, err
	}
	q := u.Query()
	q.Set("q", query)
	q.Set("limit", fmt.Sprint(maxResults))
	u.RawQuery = q.Encode()
	var payload struct {
		Pages []struct {
			Title       string `json:"title"`
			Description string `json:"description"`
			Excerpt     string `json:"excerpt"`
		} `json:"pages"`
	}
	if err := requestJSON(ctx, http.MethodGet, u.String(), "", nil, &payload); err != nil {
		return searchResponse{}, err
	}
	resp := searchResponse{Source: "Wikipedia"}
	for _, p := range payload.Pages {
		snippet := cleanText(p.Excerpt)
		if snippet == "" {
			snippet = cleanText(p.Description)
		}
		title := strings.ReplaceAll(p.Title, " ", "_")
		resp.Results = append(resp.Results, searchResult{
			Title:   cleanText(p.Title),
			URL:     "https://en.wikipedia.org/wiki/" + url.PathEscape(title),
			Snippet: snippet,
		})
	}
	return resp, nil
}

func duckDuckGoInstant(ctx context.Context, query string) (searchResponse, error) {
	endpoint := envOr("ASSISTANT_DDG_URL", "https://api.duckduckgo.com/")
	u, err := url.Parse(endpoint)
	if err != nil {
		return searchResponse{}, err
	}
	q := u.Query()
	q.Set("q", query)
	q.Set("format", "json")
	q.Set("no_html", "1")
	q.Set("skip_disambig", "1")
	u.RawQuery = q.Encode()
	var payload struct {
		Heading      string `json:"Heading"`
		AbstractText string `json:"AbstractText"`
		AbstractURL  string `json:"AbstractURL"`
		Answer       string `json:"Answer"`
	}
	if err := requestJSON(ctx, http.MethodGet, u.String(), "", nil, &payload); err != nil {
		return searchResponse{}, err
	}
	resp := searchResponse{Source: "DuckDuckGo"}
	if text := cleanText(payload.AbstractText); text != "" {
		resp.Answer = text
		if payload.Heading != "" {
			resp.Results = append(resp.Results, searchResult{Title: payload.Heading, URL: payload.AbstractURL, Snippet: text})
		}
	} else if text := cleanText(payload.Answer); text != "" {
		resp.Answer = text
	}
	return resp, nil
}

func requestJSON(ctx context.Context, method, endpoint, auth string, body []byte, out any) error {
	var reader io.Reader
	if body != nil {
		reader = strings.NewReader(string(body))
	}
	req, err := http.NewRequestWithContext(ctx, method, endpoint, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "caelestia-assistant/0.1 (web_search)")
	if auth != "" {
		req.Header.Set("Authorization", auth)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	return doJSON(req, out)
}

func doJSON(req *http.Request, out any) error {
	resp, err := searchClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		message := cleanText(string(data))
		if len(message) > 200 {
			message = message[:200]
		}
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, message)
	}
	if err := json.Unmarshal(data, out); err != nil {
		return fmt.Errorf("invalid response: %w", err)
	}
	return nil
}

func cleanText(value string) string {
	value = html.UnescapeString(tagPattern.ReplaceAllString(value, " "))
	return strings.Join(strings.Fields(value), " ")
}

func envOr(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}
