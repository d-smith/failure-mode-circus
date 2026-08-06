package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"time"
)

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

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

func calcHandler(w http.ResponseWriter, r *http.Request) {
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

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthzHandler)
	mux.HandleFunc("/calc", calcHandler)

	log.Printf("reference-service listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}
