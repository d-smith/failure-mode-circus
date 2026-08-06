import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://reference-service.internal:8080';

export const options = {
  vus: 3,
  duration: '30s',
  thresholds: {
    http_req_duration: ['p(95)<500'],
    checks: ['rate>0.99'],
  },
};

const OPERATORS = ['add', 'sub', 'mul', 'div'];

function randomInt(max) {
  return Math.floor(Math.random() * (max + 1));
}

function expectedResult(op1, op2, operator) {
  switch (operator) {
    case 'add':
      return op1 + op2;
    case 'sub':
      return op1 - op2;
    case 'mul':
      return op1 * op2;
    case 'div':
      return op1 / op2;
  }
}

export default function () {
  const op1 = randomInt(20);
  const op2 = randomInt(20);
  const operator = OPERATORS[randomInt(OPERATORS.length - 1)];

  const res = http.get(`${BASE_URL}/calc?op1=${op1}&op2=${op2}&operator=${operator}`);

  if (operator === 'div' && op2 === 0) {
    // Expected, correctly-handled error case - not a service failure.
    check(res, {
      'division by zero returns 400': (r) => r.status === 400,
    });
  } else {
    const expected = expectedResult(op1, op2, operator);
    check(res, {
      'status is 200': (r) => r.status === 200,
      'result is correct': (r) => Math.abs(r.json().result - expected) < 1e-9,
    });
  }

  sleep(1);
}
