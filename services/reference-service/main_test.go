package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHealthzHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	healthzHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if got := rec.Body.String(); got != "ok" {
		t.Errorf("body = %q, want %q", got, "ok")
	}
}

func TestCalcHandlerSuccess(t *testing.T) {
	cases := []struct {
		name           string
		op1, op2       string
		operator       string
		wantResult     float64
	}{
		{"add", "2", "3", "add", 5},
		{"sub", "2", "3", "sub", -1},
		{"mul", "4", "5", "mul", 20},
		{"div", "25", "5", "div", 5},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/calc?op1="+tc.op1+"&op2="+tc.op2+"&operator="+tc.operator, nil)
			rec := httptest.NewRecorder()

			calcHandler(rec, req)

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
	req := httptest.NewRequest(http.MethodGet, "/calc?op1=1&op2=0&operator=div", nil)
	rec := httptest.NewRecorder()

	calcHandler(rec, req)

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
	req := httptest.NewRequest(http.MethodGet, "/calc?op1=1&op2=2&operator=xyz", nil)
	rec := httptest.NewRecorder()

	calcHandler(rec, req)

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
			req := httptest.NewRequest(http.MethodGet, tc.url, nil)
			rec := httptest.NewRecorder()

			calcHandler(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
			}
		})
	}
}

func TestCalcHandlerMethodNotAllowed(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/calc?op1=1&op2=2&operator=add", nil)
	rec := httptest.NewRecorder()

	calcHandler(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusMethodNotAllowed)
	}
}
