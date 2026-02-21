export interface ResponseInit {
  status?: number;
  headers?: Record<string, string>;
}

export function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status: init.status ?? 200,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...(init.headers ?? {}),
    },
  });
}

export function htmlResponse(body: string, init: ResponseInit = {}): Response {
  return new Response(body, {
    status: init.status ?? 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      ...(init.headers ?? {}),
    },
  });
}

export function parseBoolean(
  raw: string | null | undefined,
  fallback: boolean
): boolean {
  if (raw === undefined || raw === null || raw === "") {
    return fallback;
  }
  const value = String(raw).toLowerCase();
  if (value === "1" || value === "true" || value === "yes" || value === "on") {
    return true;
  }
  if (value === "0" || value === "false" || value === "no" || value === "off") {
    return false;
  }
  return fallback;
}

export function normalizeInt(
  raw: string | number | null | undefined,
  fallback: number,
  min: number,
  max: number
): number {
  const parsed = Number.parseInt(String(raw ?? fallback), 10);
  const safe = Number.isFinite(parsed) ? parsed : fallback;
  return Math.max(min, Math.min(max, safe));
}
