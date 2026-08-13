package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"
)

type calcResponse struct {
	Op1      float64 `json:"op1"`
	Op2      float64 `json:"op2"`
	Operator string  `json:"operator"`
	Result   float64 `json:"result"`
}

type errorResponse struct {
	Error string `json:"error"`
}

func writeJSONError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(errorResponse{Error: msg})
}

// serviceState tracks the error-state fault injection: after callThreshold
// successful /calc calls, both /calc and /healthz return 503 for
// errorDuration before auto-recovering.
type serviceState struct {
	mu            sync.Mutex
	callThreshold int
	errorDuration time.Duration
	count         int
	errorUntil    time.Time // zero value = not in error state
}

func newServiceState(callThreshold int, errorDuration time.Duration) *serviceState {
	return &serviceState{callThreshold: callThreshold, errorDuration: errorDuration}
}

// inErrorState reports whether the service is currently in its error
// state, lazily resetting (exiting error state, counter -> 0) if the
// configured duration has elapsed since entry.
func (s *serviceState) inErrorState(now time.Time) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.errorUntil.IsZero() {
		return false
	}
	if now.Before(s.errorUntil) {
		return true
	}
	s.errorUntil = time.Time{}
	s.count = 0
	return false
}

// recordSuccess counts one successful /calc call, entering error state
// once callThreshold is reached. No-op if callThreshold <= 0.
func (s *serviceState) recordSuccess(now time.Time) {
	if s.callThreshold <= 0 {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.count++
	if s.count >= s.callThreshold {
		s.errorUntil = now.Add(s.errorDuration)
	}
}

func (s *serviceState) healthzHandler(w http.ResponseWriter, r *http.Request) {
	if s.inErrorState(time.Now()) {
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte("error"))
		return
	}
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

func (s *serviceState) calcHandler(w http.ResponseWriter, r *http.Request) {
	if s.inErrorState(time.Now()) {
		writeJSONError(w, http.StatusServiceUnavailable, "service is in error state")
		return
	}

	if r.Method != http.MethodGet {
		writeJSONError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	op1, err1 := strconv.ParseFloat(r.URL.Query().Get("op1"), 64)
	op2, err2 := strconv.ParseFloat(r.URL.Query().Get("op2"), 64)
	if err1 != nil || err2 != nil {
		writeJSONError(w, http.StatusBadRequest, "op1 and op2 must be numeric")
		return
	}

	operator := r.URL.Query().Get("operator")
	var result float64
	switch operator {
	case "add":
		result = op1 + op2
	case "sub":
		result = op1 - op2
	case "mul":
		result = op1 * op2
	case "div":
		if op2 == 0 {
			writeJSONError(w, http.StatusBadRequest, "division by zero")
			return
		}
		result = op1 / op2
	default:
		writeJSONError(w, http.StatusBadRequest, "operator must be one of add, sub, mul, div")
		return
	}

	s.recordSuccess(time.Now())

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(calcResponse{Op1: op1, Op2: op2, Operator: operator, Result: result})
}

func runHealthcheck(addr string) int {
	_, port, err := net.SplitHostPort(addr)
	if err != nil || port == "" {
		port = "8080"
	}

	client := http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(fmt.Sprintf("http://127.0.0.1:%s/healthz", port))
	if err != nil {
		return 1
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}

func main() {
	addr := os.Getenv("LISTEN_ADDR")
	if addr == "" {
		addr = ":8080"
	}

	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		os.Exit(runHealthcheck(addr))
	}

	callThreshold := 0
	if v := os.Getenv("CALL_THRESHOLD"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			callThreshold = n
		}
	}
	errorDurationSeconds := 120
	if v := os.Getenv("ERROR_STATE_DURATION_SECONDS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			errorDurationSeconds = n
		}
	}
	state := newServiceState(callThreshold, time.Duration(errorDurationSeconds)*time.Second)

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", state.healthzHandler)
	mux.HandleFunc("/calc", state.calcHandler)

	log.Printf("reference-service listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}
