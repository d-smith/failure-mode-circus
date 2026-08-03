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

export default function () {
  const res = http.get(`${BASE_URL}/healthz`);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'body is ok': (r) => r.body === 'ok',
  });

  sleep(1);
}
