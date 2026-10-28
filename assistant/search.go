package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	stdhtml "html"
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
	xhtml "golang.org/x/net/html"
)

const webSearchToolName = "web_search"

const webSearchDescription = `Search the web for current information: news, facts, people, places, prices, releases, or anything you are unsure about. Returns top sources with titles, URLs, and snippets. Prefer primary sources, cite the source URLs in your answer, and keep the answer to at most three sentences. Google-style operators (site:, -site:, after:, before:, inurl:, intitle:, filetype:, "exact phrase", -term, OR) are supported where the backend allows them.`

const webSearchParameters = `{
  "type": "object",
  "properties": {
    "query": {"type": "string", "description": "The search query, in natural language or keywords."},
    "recency": {"type": "string", "enum": ["day", "week", "month", "year"], "description": "Optional relative time filter."},
    "limit": {"type": "integer", "minimum": 1, "maximum": 10, "description": "How many sources to return. Default 5."}
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
	tagPattern         = regexp.MustCompile(`<[^>]+>`)
	mdLinkPattern      = regexp.MustCompile(`\[([^\]]*)\]\([^)]+\)`)
	mdLinkTailPattern  = regexp.MustCompile(`\]\([^)]+\)`)
	mdImagePattern     = regexp.MustCompile(`!\[[^\]]*\]\([^)]+\)`)
	mdHeadingPattern   = regexp.MustCompile(`(?m)^#{1,6}\s*`)
	sentencePattern    = regexp.MustCompile(`[^.!?]+[.!?]*`)
	boilerplatePattern = regexp.MustCompile(`(?i)citation|copy citation|manual of style|fact-checked|last updated|select citation`)
	leadingDatePattern = regexp.MustCompile(`^\s*(?:\d{1,4}[,/]\s*)*(?:\d{4}\s*)?`)
	spacePattern       = regexp.MustCompile(`\s+`)
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
		Query   string `json:"query"`
		Recency string `json:"recency"`
		Limit   int    `json:"limit"`
	}
	if err := json.Unmarshal(params, &args); err != nil {
		return searchError("invalid arguments: " + err.Error()), nil
	}
	query := strings.TrimSpace(args.Query)
	if query == "" {
		return searchError("query is required"), nil
	}
	limit := args.Limit
	if limit <= 0 {
		limit = 5
	}
	if limit > 10 {
		limit = 10
	}
	recency := strings.ToLower(strings.TrimSpace(args.Recency))
	switch recency {
	case "", "day", "week", "month", "year":
	default:
		recency = ""
	}

	callCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

	resp, err := searchWeb(callCtx, query, recency, limit)
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

func searchWeb(ctx context.Context, query, recency string, limit int) (searchResponse, error) {
	key := query + "\x00" + recency + "\x00" + fmt.Sprint(limit)
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
	try := func(name string, fn func(context.Context) (searchResponse, error)) (searchResponse, bool) {
		resp, err := fn(ctx)
		if err == nil && (resp.Answer != "" || len(resp.Results) > 0) {
			storeSearch(key, resp, "")
			return resp, true
		}
		if err != nil {
			errs = append(errs, name+": "+err.Error())
		}
		return searchResponse{}, false
	}

	if resp, ok := try("parallel", func(ctx context.Context) (searchResponse, error) {
		return parallelMCPSearch(ctx, query, limit)
	}); ok {
		return resp, nil
	}
	if resp, ok := try("exa", func(ctx context.Context) (searchResponse, error) {
		return exaMCPSearch(ctx, query, limit)
	}); ok {
		return resp, nil
	}
	if resp, ok := try("duckduckgo", func(ctx context.Context) (searchResponse, error) {
		return duckDuckGoSearch(ctx, query, recency, limit)
	}); ok {
		return resp, nil
	}
	if resp, ok := try("wikipedia", func(ctx context.Context) (searchResponse, error) {
		return wikipediaSearch(ctx, query, limit)
	}); ok {
		return resp, nil
	}
	if resp, ok := try("duckduckgo-instant", func(ctx context.Context) (searchResponse, error) {
		return duckDuckGoInstant(ctx, query)
	}); ok {
		return resp, nil
	}

	message := "no results"
	if len(errs) > 0 {
		message += " (" + strings.Join(errs, "; ") + ")"
	}
	storeSearch(key, searchResponse{}, message)
	return searchResponse{}, fmt.Errorf("%s", message)
}

func storeSearch(key string, resp searchResponse, err string) {
	searchCache.Lock()
	searchCache.entries[key] = cachedSearch{at: time.Now(), resp: resp, err: err}
	for k, entry := range searchCache.entries {
		if time.Since(entry.at) > 10*time.Minute {
			delete(searchCache.entries, k)
		}
	}
	searchCache.Unlock()
}

type mcpResponse struct {
	Result struct {
		Content []struct {
			Text string `json:"text"`
		} `json:"content"`
	} `json:"result"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error"`
}

func parallelMCPSearch(ctx context.Context, query string, limit int) (searchResponse, error) {
	endpoint := envOr("ASSISTANT_PARALLEL_MCP_URL", "https://search.parallel.ai/mcp")
	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "web_search",
			"arguments": map[string]any{
				"objective":      query,
				"search_queries": []string{query},
			},
		},
	})
	if err != nil {
		return searchResponse{}, err
	}
	data, err := requestData(ctx, http.MethodPost, endpoint, map[string]string{
		"Content-Type": "application/json",
	}, body)
	if err != nil {
		return searchResponse{}, err
	}
	var envelope mcpResponse
	if err := json.Unmarshal(data, &envelope); err != nil {
		return searchResponse{}, fmt.Errorf("invalid MCP response: %w", err)
	}
	if envelope.Error != nil {
		return searchResponse{}, fmt.Errorf("MCP error: %s", envelope.Error.Message)
	}
	if len(envelope.Result.Content) == 0 {
		return searchResponse{}, fmt.Errorf("empty MCP response")
	}
	var payload struct {
		Results []struct {
			URL         string   `json:"url"`
			Title       string   `json:"title"`
			PublishDate string   `json:"publish_date"`
			Excerpts    []string `json:"excerpts"`
		} `json:"results"`
	}
	if err := json.Unmarshal([]byte(envelope.Result.Content[0].Text), &payload); err != nil {
		return searchResponse{}, fmt.Errorf("invalid Parallel payload: %w", err)
	}
	resp := searchResponse{Source: "Parallel"}
	for _, result := range payload.Results {
		if len(resp.Results) >= limit {
			break
		}
		snippet := ""
		if len(result.Excerpts) > 0 {
			snippet = bestSnippet(strings.Join(result.Excerpts, " "), query, 400)
		}
		resp.Results = append(resp.Results, searchResult{
			Title:   cleanSnippet(result.Title),
			URL:     result.URL,
			Snippet: snippet,
		})
	}
	return resp, nil
}

func exaMCPSearch(ctx context.Context, query string, limit int) (searchResponse, error) {
	endpoint := envOr("ASSISTANT_EXA_MCP_URL", "https://mcp.exa.ai/mcp?tools=web_search_exa")
	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "web_search_exa",
			"arguments": map[string]any{
				"query":      query,
				"numResults": limit,
			},
		},
	})
	if err != nil {
		return searchResponse{}, err
	}
	data, err := requestData(ctx, http.MethodPost, endpoint, map[string]string{
		"Content-Type": "application/json",
		"Accept":       "application/json, text/event-stream",
	}, body)
	if err != nil {
		return searchResponse{}, err
	}
	data = decodeSSE(data)
	var envelope mcpResponse
	if err := json.Unmarshal(data, &envelope); err != nil {
		return searchResponse{}, fmt.Errorf("invalid MCP response: %w", err)
	}
	if envelope.Error != nil {
		return searchResponse{}, fmt.Errorf("MCP error: %s", envelope.Error.Message)
	}
	if len(envelope.Result.Content) == 0 {
		return searchResponse{}, fmt.Errorf("empty MCP response")
	}
	resp := searchResponse{Source: "Exa"}
	for _, block := range strings.Split(envelope.Result.Content[0].Text, "\n---\n") {
		if len(resp.Results) >= limit {
			break
		}
		result, ok := parseExaBlock(block, query)
		if ok {
			resp.Results = append(resp.Results, result)
		}
	}
	if len(resp.Results) == 0 {
		return searchResponse{}, fmt.Errorf("no parseable Exa results")
	}
	return resp, nil
}

func parseExaBlock(block, query string) (searchResult, bool) {
	var result searchResult
	lines := strings.Split(block, "\n")
	highlights := -1
	for i, line := range lines {
		line = strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(line, "Title:"):
			result.Title = strings.TrimSpace(strings.TrimPrefix(line, "Title:"))
		case strings.HasPrefix(line, "URL:"):
			result.URL = strings.TrimSpace(strings.TrimPrefix(line, "URL:"))
		case strings.HasPrefix(line, "Highlights:"):
			highlights = i + 1
		}
		if highlights >= 0 && i >= highlights {
			break
		}
	}
	if result.URL == "" || !strings.HasPrefix(result.URL, "http") {
		return searchResult{}, false
	}
	if result.Title == "" || result.Title == "N/A" {
		if parsed, err := url.Parse(result.URL); err == nil {
			result.Title = parsed.Host
		}
	}
	if highlights >= 0 && highlights < len(lines) {
		result.Snippet = bestSnippet(strings.Join(lines[highlights:], " "), query, 400)
	}
	return result, true
}

func duckDuckGoSearch(ctx context.Context, query, recency string, limit int) (searchResponse, error) {
	endpoint := envOr("ASSISTANT_DDG_URL", "https://html.duckduckgo.com/html/")
	form := url.Values{}
	form.Set("q", query)
	form.Set("kl", "us-en")
	switch recency {
	case "day":
		form.Set("df", "d")
	case "week":
		form.Set("df", "w")
	case "month":
		form.Set("df", "m")
	case "year":
		form.Set("df", "y")
	}
	data, err := requestData(ctx, http.MethodPost, endpoint, map[string]string{
		"Content-Type": "application/x-www-form-urlencoded",
		"Accept":       "text/html",
	}, []byte(form.Encode()))
	if err != nil {
		return searchResponse{}, err
	}
	page := string(data)
	if strings.Contains(page, "anomaly-modal") || strings.Contains(page, "anomaly.js") {
		return searchResponse{}, fmt.Errorf("bot challenge")
	}
	doc, err := xhtml.Parse(bytes.NewReader(data))
	if err != nil {
		return searchResponse{}, err
	}
	var results []searchResult
	var walk func(*xhtml.Node)
	walk = func(node *xhtml.Node) {
		if len(results) >= limit {
			return
		}
		if node.Type == xhtml.ElementNode && node.Data == "div" && hasClass(node, "result") && !hasClass(node, "result__") {
			if result, ok := parseDDGResult(node, query); ok {
				results = append(results, result)
			}
		}
		for child := node.FirstChild; child != nil; child = child.NextSibling {
			walk(child)
		}
	}
	walk(doc)
	if len(results) == 0 {
		return searchResponse{}, fmt.Errorf("no results")
	}
	return searchResponse{Results: results, Source: "DuckDuckGo"}, nil
}

func parseDDGResult(node *xhtml.Node, query string) (searchResult, bool) {
	var link *xhtml.Node
	var snippet string
	var find func(*xhtml.Node)
	find = func(n *xhtml.Node) {
		if n.Type == xhtml.ElementNode && n.Data == "a" && hasClass(n, "result__a") && link == nil {
			link = n
		}
		if (n.Type == xhtml.ElementNode && (n.Data == "a" || n.Data == "div" || n.Data == "span")) && hasClass(n, "result__snippet") && snippet == "" {
			snippet = nodeText(n)
		}
		for child := n.FirstChild; child != nil; child = child.NextSibling {
			find(child)
		}
	}
	find(node)
	if link == nil {
		return searchResult{}, false
	}
	href := attr(link, "href")
	target := unwrapDDGURL(href)
	if target == "" {
		return searchResult{}, false
	}
	title := cleanSnippet(nodeText(link))
	if title == "" {
		return searchResult{}, false
	}
	return searchResult{Title: title, URL: target, Snippet: bestSnippet(snippet, query, 400)}, true
}

func wikipediaSearch(ctx context.Context, query string, limit int) (searchResponse, error) {
	endpoint := envOr("ASSISTANT_WIKI_URL", "https://en.wikipedia.org/w/rest.php/v1/search/page")
	u, err := url.Parse(endpoint)
	if err != nil {
		return searchResponse{}, err
	}
	q := u.Query()
	q.Set("q", query)
	q.Set("limit", fmt.Sprint(limit))
	u.RawQuery = q.Encode()
	data, err := requestData(ctx, http.MethodGet, u.String(), nil, nil)
	if err != nil {
		return searchResponse{}, err
	}
	var payload struct {
		Pages []struct {
			Title       string `json:"title"`
			Description string `json:"description"`
			Excerpt     string `json:"excerpt"`
		} `json:"pages"`
	}
	if err := json.Unmarshal(data, &payload); err != nil {
		return searchResponse{}, fmt.Errorf("invalid response: %w", err)
	}
	resp := searchResponse{Source: "Wikipedia"}
	for _, page := range payload.Pages {
		snippet := cleanSnippet(page.Excerpt)
		if snippet == "" {
			snippet = cleanSnippet(page.Description)
		}
		title := strings.ReplaceAll(page.Title, " ", "_")
		resp.Results = append(resp.Results, searchResult{
			Title:   cleanSnippet(page.Title),
			URL:     "https://en.wikipedia.org/wiki/" + url.PathEscape(title),
			Snippet: limitText(snippet, 400),
		})
	}
	return resp, nil
}

func duckDuckGoInstant(ctx context.Context, query string) (searchResponse, error) {
	endpoint := envOr("ASSISTANT_DDG_INSTANT_URL", "https://api.duckduckgo.com/")
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
	data, err := requestData(ctx, http.MethodGet, u.String(), nil, nil)
	if err != nil {
		return searchResponse{}, err
	}
	var payload struct {
		Heading      string `json:"Heading"`
		AbstractText string `json:"AbstractText"`
		AbstractURL  string `json:"AbstractURL"`
		Answer       string `json:"Answer"`
	}
	if err := json.Unmarshal(data, &payload); err != nil {
		return searchResponse{}, fmt.Errorf("invalid response: %w", err)
	}
	resp := searchResponse{Source: "DuckDuckGo"}
	if text := cleanSnippet(payload.AbstractText); text != "" {
		resp.Answer = text
		if payload.Heading != "" {
			resp.Results = append(resp.Results, searchResult{Title: cleanSnippet(payload.Heading), URL: payload.AbstractURL, Snippet: limitText(text, 400)})
		}
	} else if text := cleanSnippet(payload.Answer); text != "" {
		resp.Answer = text
	}
	return resp, nil
}

func requestData(ctx context.Context, method, endpoint string, headers map[string]string, body []byte) ([]byte, error) {
	var reader io.Reader
	if body != nil {
		reader = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, endpoint, reader)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
	req.Header.Set("Accept-Language", "en-US,en;q=0.9")
	for key, value := range headers {
		req.Header.Set(key, value)
	}
	resp, err := searchClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		message := limitText(cleanSnippet(string(data)), 200)
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, message)
	}
	return data, nil
}

func decodeSSE(data []byte) []byte {
	if !bytes.Contains(data, []byte("data:")) {
		return data
	}
	var last []byte
	for _, line := range bytes.Split(data, []byte("\n")) {
		line = bytes.TrimSpace(line)
		if bytes.HasPrefix(line, []byte("data:")) {
			last = bytes.TrimSpace(line[len("data:"):])
		}
	}
	if len(last) > 0 {
		return last
	}
	return data
}

func hasClass(node *xhtml.Node, class string) bool {
	for _, attr := range node.Attr {
		if attr.Key != "class" {
			continue
		}
		for _, value := range strings.Fields(attr.Val) {
			if value == class {
				return true
			}
		}
	}
	return false
}

func attr(node *xhtml.Node, key string) string {
	for _, attr := range node.Attr {
		if attr.Key == key {
			return attr.Val
		}
	}
	return ""
}

func nodeText(node *xhtml.Node) string {
	var b strings.Builder
	var walk func(*xhtml.Node)
	walk = func(n *xhtml.Node) {
		if n.Type == xhtml.TextNode {
			b.WriteString(n.Data)
		}
		for child := n.FirstChild; child != nil; child = child.NextSibling {
			walk(child)
		}
	}
	walk(node)
	return b.String()
}

func unwrapDDGURL(href string) string {
	href = strings.ReplaceAll(href, "&amp;", "&")
	if match := regexp.MustCompile(`[?&]uddg=([^&]+)`).FindStringSubmatch(href); len(match) == 2 {
		if decoded, err := url.QueryUnescape(match[1]); err == nil {
			return decoded
		}
	}
	if strings.HasPrefix(href, "//") {
		return "https:" + href
	}
	if strings.HasPrefix(href, "http://") || strings.HasPrefix(href, "https://") {
		return href
	}
	return ""
}

func cleanSnippet(value string) string {
	value = stdhtml.UnescapeString(tagPattern.ReplaceAllString(value, " "))
	value = mdImagePattern.ReplaceAllString(value, " ")
	value = mdLinkPattern.ReplaceAllString(value, "$1")
	value = mdLinkTailPattern.ReplaceAllString(value, " ")
	value = mdHeadingPattern.ReplaceAllString(value, " ")
	value = strings.ReplaceAll(value, "**", "")
	value = strings.ReplaceAll(value, "`", "")
	value = spacePattern.ReplaceAllString(value, " ")
	return strings.TrimSpace(value)
}

func bestSnippet(text, query string, max int) string {
	text = cleanSnippet(text)
	if text == "" {
		return ""
	}
	terms := queryTerms(query)
	if len(terms) == 0 {
		return limitText(text, max)
	}
	sentences := sentencePattern.FindAllString(text, -1)
	best, bestScore := "", -1
	for _, sentence := range sentences {
		sentence = strings.TrimSpace(sentence)
		if sentence == "" {
			continue
		}
		lower := strings.ToLower(sentence)
		score := 0
		for _, term := range terms {
			if strings.Contains(lower, term) {
				score++
			}
		}
		if strings.Contains(lower, " is ") || strings.Contains(lower, " are ") || strings.Contains(lower, " was ") {
			score += 2
		}
		if strings.HasSuffix(strings.TrimSpace(sentence), "?") {
			score -= 5
		}
		if boilerplatePattern.MatchString(sentence) {
			score -= 3
		}
		if score > bestScore {
			best, bestScore = sentence, score
		}
	}
	if best == "" {
		return limitText(text, max)
	}
	best = strings.TrimSpace(leadingDatePattern.ReplaceAllString(best, ""))
	if best == "" {
		return limitText(text, max)
	}
	return limitText(best, max)
}

func queryTerms(query string) []string {
	seen := map[string]bool{}
	var terms []string
	for _, field := range strings.Fields(strings.ToLower(query)) {
		field = strings.Trim(field, `"'()[]{}:,.!?`)
		if len(field) < 3 || seen[field] {
			continue
		}
		seen[field] = true
		terms = append(terms, field)
	}
	return terms
}

func limitText(value string, max int) string {
	if len(value) <= max {
		return value
	}
	return strings.TrimSpace(value[:max]) + "…"
}

func envOr(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}
