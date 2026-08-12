package main

import (
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestHealthzHandler(t *testing.T) {
	state := newServiceState(0, 0)
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	state.healthzHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if got := rec.Body.String(); got != "ok" {
		t.Errorf("body = %q, want %q", got, "ok")
	}
}

func TestCalcHandlerSuccess(t *testing.T) {
	cases := []struct {
		name       string
		op1, op2   string
		operator   string
		wantResult float64
	}{
		{"add", "2", "3", "add", 5},
		{"sub", "2", "3", "sub", -1},
		{"mul", "4", "5", "mul", 20},
		{"div", "25", "5", "div", 5},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			state := newServiceState(0, 0)
			req := httptest.NewRequest(http.MethodGet, "/calc?op1="+tc.op1+"&op2="+tc.op2+"&operator="+tc.operator, nil)
			rec := httptest.NewRecorder()

			state.calcHandler(rec, req)

			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want %d (body: %s)", rec.Code, http.StatusOK, rec.Body.String())
			}

			var got calcResponse
			if err := json.NewDecoder(rec.Body).Decode(&got); err != nil {
				t.Fatalf("decode response: %v", err)
			}
			if got.Result != tc.wantResult {
				t.Errorf("result = %v, want %v", got.Result, tc.wantResult)
			}
			if got.Operator != tc.operator {
				t.Errorf("operator = %q, want %q", got.Operator, tc.operator)
			}
		})
	}
}

func TestCalcHandlerDivideByZero(t *testing.T) {
	state := newServiceState(0, 0)
	req := httptest.NewRequest(http.MethodGet, "/calc?op1=1&op2=0&operator=div", nil)
	rec := httptest.NewRecorder()

	state.calcHandler(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}

	var got errorResponse
	if err := json.NewDecoder(rec.Body).Decode(&got); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if !strings.Contains(got.Error, "division by zero") {
		t.Errorf("error = %q, want it to mention division by zero", got.Error)
	}
}

func TestCalcHandlerInvalidOperator(t *testing.T) {
	state := newServiceState(0, 0)
	req := httptest.NewRequest(http.MethodGet, "/calc?op1=1&op2=2&operator=xyz", nil)
	rec := httptest.NewRecorder()

	state.calcHandler(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}

func TestCalcHandlerInvalidOperands(t *testing.T) {
	cases := []struct {
		name string
		url  string
	}{
		{"non-numeric op1", "/calc?op1=abc&op2=2&operator=add"},
		{"non-numeric op2", "/calc?op1=1&op2=xyz&operator=add"},
		{"missing op1", "/calc?op2=2&operator=add"},
		{"missing op2", "/calc?op1=1&operator=add"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			state := newServiceState(0, 0)
			req := httptest.NewRequest(http.MethodGet, tc.url, nil)
			rec := httptest.NewRecorder()

			state.calcHandler(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
			}
		})
	}
}

func TestCalcHandlerMethodNotAllowed(t *testing.T) {
	state := newServiceState(0, 0)
	req := httptest.NewRequest(http.MethodPost, "/calc?op1=1&op2=2&operator=add", nil)
	rec := httptest.NewRecorder()

	state.calcHandler(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusMethodNotAllowed)
	}
}

func TestCalcHandlerErrorState(t *testing.T) {
	state := newServiceState(2, 50*time.Millisecond)

	// A bad-operand call before tripping shouldn't count toward the threshold.
	badReq := httptest.NewRequest(http.MethodGet, "/calc?op1=abc&op2=2&operator=add", nil)
	state.calcHandler(httptest.NewRecorder(), badReq)

	for i := 0; i < 2; i++ {
		req := httptest.NewRequest(http.MethodGet, "/calc?op1=1&op2=1&operator=add", nil)
		rec := httptest.NewRecorder()
		state.calcHandler(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("call %d: status = %d, want %d", i+1, rec.Code, http.StatusOK)
		}
	}

	req := httptest.NewRequest(http.MethodGet, "/calc?op1=1&op2=1&operator=add", nil)
	rec := httptest.NewRecorder()
	state.calcHandler(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusServiceUnavailable)
	}

	var got errorResponse
	if err := json.NewDecoder(rec.Body).Decode(&got); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if !strings.Contains(got.Error, "error state") {
		t.Errorf("error = %q, want it to mention error state", got.Error)
	}
}

func TestHealthzHandlerErrorState(t *testing.T) {
	state := newServiceState(2, 50*time.Millisecond)

	for i := 0; i < 2; i++ {
		req := httptest.NewRequest(http.MethodGet, "/calc?op1=1&op2=1&operator=add", nil)
		state.calcHandler(httptest.NewRecorder(), req)
	}

	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()
	state.healthzHandler(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusServiceUnavailable)
	}
}

func TestErrorStateAutoRecovery(t *testing.T) {
	state := newServiceState(2, 50*time.Millisecond)

	for i := 0; i < 2; i++ {
		req := httptest.NewRequest(http.MethodGet, "/calc?op1=1&op2=1&operator=add", nil)
		state.calcHandler(httptest.NewRecorder(), req)
	}

	trippedReq := httptest.NewRequest(http.MethodGet, "/calc?op1=1&op2=1&operator=add", nil)
	trippedRec := httptest.NewRecorder()
	state.calcHandler(trippedRec, trippedReq)
	if trippedRec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status while tripped = %d, want %d", trippedRec.Code, http.StatusServiceUnavailable)
	}

	time.Sleep(60 * time.Millisecond)

	healthzReq := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	healthzRec := httptest.NewRecorder()
	state.healthzHandler(healthzRec, healthzReq)
	if healthzRec.Code != http.StatusOK {
		t.Fatalf("healthz status after recovery = %d, want %d", healthzRec.Code, http.StatusOK)
	}

	// Counter should have reset - one more success shouldn't re-trip.
	calcReq := httptest.NewRequest(http.MethodGet, "/calc?op1=1&op2=1&operator=add", nil)
	calcRec := httptest.NewRecorder()
	state.calcHandler(calcRec, calcReq)
	if calcRec.Code != http.StatusOK {
		t.Fatalf("calc status after recovery = %d, want %d", calcRec.Code, http.StatusOK)
	}
}

func TestCalcHandlerThresholdDisabled(t *testing.T) {
	state := newServiceState(0, 50*time.Millisecond)

	for i := 0; i < 10; i++ {
		req := httptest.NewRequest(http.MethodGet, "/calc?op1=1&op2=1&operator=add", nil)
		rec := httptest.NewRecorder()
		state.calcHandler(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("call %d: status = %d, want %d", i+1, rec.Code, http.StatusOK)
		}
	}
}

func TestRunHealthcheckSuccess(t *testing.T) {
	state := newServiceState(0, 0)
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", state.healthzHandler)
	server := httptest.NewServer(mux)
	defer server.Close()

	got := runHealthcheck(server.Listener.Addr().String())
	if got != 0 {
		t.Errorf("runHealthcheck() = %d, want 0", got)
	}
}

func TestRunHealthcheckFailure(t *testing.T) {
	// Reserve a free port, then release it immediately so nothing is
	// listening there when runHealthcheck tries to reach it.
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("net.Listen: %v", err)
	}
	addr := ln.Addr().String()
	ln.Close()

	got := runHealthcheck(addr)
	if got != 1 {
		t.Errorf("runHealthcheck() = %d, want 1", got)
	}
}
