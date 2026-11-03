package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"os"
	"strings"
	"time"
)

type luciClient struct {
	baseURL    *url.URL
	httpClient *http.Client
}

func normalizeBaseURL(host, scheme string) (*url.URL, error) {
	host = strings.TrimSpace(host)
	if host == "" {
		return nil, errors.New("host is required")
	}
	if !strings.Contains(host, "://") {
		if scheme == "" {
			scheme = "http"
		}
		host = scheme + "://" + host
	}
	u, err := url.Parse(host)
	if err != nil {
		return nil, err
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return nil, fmt.Errorf("unsupported URL scheme %q", u.Scheme)
	}
	if u.Host == "" || u.User != nil {
		return nil, errors.New("host must not contain credentials")
	}
	u.Path, u.RawQuery, u.Fragment = "", "", ""
	return u, nil
}

func endpointURL(base *url.URL, prefix, path string) (string, error) {
	prefix = "/" + strings.Trim(strings.TrimSpace(prefix), "/")
	path = "/" + strings.Trim(strings.TrimSpace(path), "/")
	if strings.Contains(path, "..") {
		return "", errors.New("endpoint path must not contain '..'")
	}
	u := *base
	u.Path = strings.TrimSuffix(prefix, "/") + path
	return u.String(), nil
}

func newLuCIClient(host, scheme string, insecure bool, timeout time.Duration) (*luciClient, error) {
	base, err := normalizeBaseURL(host, scheme)
	if err != nil {
		return nil, err
	}
	jar, err := cookiejar.New(nil)
	if err != nil {
		return nil, err
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	if insecure {
		transport.TLSClientConfig = &tls.Config{InsecureSkipVerify: true} //nolint:gosec
	}
	return &luciClient{baseURL: base, httpClient: &http.Client{
		Jar: jar, Transport: transport, Timeout: timeout,
	}}, nil
}

func (c *luciClient) login(ctx context.Context, username, password string) error {
	if strings.TrimSpace(username) == "" || password == "" {
		return errors.New("LuCI username and password are required")
	}
	form := url.Values{"luci_username": {username}, "luci_password": {password}}
	loginURL := *c.baseURL
	loginURL.Path = "/cgi-bin/luci/"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, loginURL.String(), strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 400 {
		return fmt.Errorf("login failed: HTTP %s", resp.Status)
	}
	for _, cookie := range c.httpClient.Jar.Cookies(c.baseURL) {
		if strings.HasPrefix(cookie.Name, "sysauth") && cookie.Value != "" {
			return nil
		}
	}
	return errors.New("login failed: no LuCI authentication cookie returned")
}

func (c *luciClient) request(ctx context.Context, method, prefix, path, body string) ([]byte, error) {
	endpoint, err := endpointURL(c.baseURL, prefix, path)
	if err != nil {
		return nil, err
	}
	var reader io.Reader
	if body != "" {
		reader = bytes.NewBufferString(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, endpoint, reader)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	if body != "" {
		req.Header.Set("Content-Type", "application/json;charset=utf-8")
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 8*1024*1024+1))
	if err != nil {
		return nil, err
	}
	if len(data) > 8*1024*1024 {
		return nil, errors.New("response exceeded 8 MiB limit")
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return data, fmt.Errorf("request failed: HTTP %s", resp.Status)
	}
	return data, nil
}

func requireWriteApproval(method string, approved bool) error {
	method = strings.ToUpper(method)
	if method == http.MethodGet || method == http.MethodHead {
		return nil
	}
	if !approved && os.Getenv("TARGET_HTTP_WRITE_APPROVED") != "YES" {
		return errors.New("mutating HTTP request requires explicit approval")
	}
	return nil
}

func main() {
	var host, scheme, username, passwordEnv, prefix string
	var insecure, approveWrite bool
	var timeoutSeconds int
	flag.StringVar(&host, "host", "", "target host or base URL")
	flag.StringVar(&scheme, "scheme", "http", "default scheme")
	flag.StringVar(&username, "user", "", "LuCI username")
	flag.StringVar(&passwordEnv, "password-env", "", "environment variable containing the password")
	flag.StringVar(&prefix, "prefix", "/cgi-bin/luci", "endpoint prefix after login")
	flag.BoolVar(&insecure, "insecure", false, "explicitly allow an untrusted HTTPS certificate")
	flag.BoolVar(&approveWrite, "approve-write", false, "record approval for a mutating request")
	flag.IntVar(&timeoutSeconds, "timeout", 30, "request timeout in seconds")
	flag.Parse()

	args := flag.Args()
	if len(args) < 2 || len(args) > 3 {
		fmt.Fprintln(os.Stderr, "usage: lucihttp [flags] METHOD PATH [BODY]")
		os.Exit(2)
	}
	method := strings.ToUpper(args[0])
	if _, err := http.NewRequest(method, "http://example.invalid", nil); err != nil {
		exitErr("invalid HTTP method")
	}
	if err := requireWriteApproval(method, approveWrite); err != nil {
		exitErr(err.Error())
	}
	if timeoutSeconds < 1 || timeoutSeconds > 300 {
		exitErr("timeout must be between 1 and 300 seconds")
	}
	password := os.Getenv(passwordEnv)
	if passwordEnv == "" || password == "" {
		exitErr("--password-env must name a non-empty environment variable")
	}
	client, err := newLuCIClient(host, scheme, insecure, time.Duration(timeoutSeconds)*time.Second)
	if err != nil {
		exitErr(err.Error())
	}
	if err := client.login(context.Background(), username, password); err != nil {
		exitErr(err.Error())
	}
	body := ""
	if len(args) == 3 {
		body = args[2]
	}
	data, err := client.request(context.Background(), method, prefix, args[1], body)
	if len(data) != 0 {
		_, _ = os.Stdout.Write(data)
		if data[len(data)-1] != '\n' {
			fmt.Println()
		}
	}
	if err != nil {
		exitErr(err.Error())
	}
}

func exitErr(message string) {
	fmt.Fprintln(os.Stderr, message)
	os.Exit(1)
}
