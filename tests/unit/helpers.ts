// Fakes for driving the Node request handler without opening a port.

export interface FakeResponse {
  statusCode: number
  headers: Record<string, string>
  body: string
  json(): any
}

/** Calls `handler` with a fake request and resolves with what it wrote. */
export function callApi(
  handler: (req: any, res: any, next?: () => void) => Promise<unknown>,
  method: string,
  url: string,
  headers: Record<string, string> = {},
): Promise<FakeResponse> {
  return new Promise((resolve) => {
    const res = {
      statusCode: 200,
      headers: {} as Record<string, string>,
      body: '',
      setHeader(name: string, value: string) { this.headers[name] = value },
      end(chunk = '') {
        this.body = String(chunk)
        resolve({ statusCode: this.statusCode, headers: this.headers, body: this.body, json: () => JSON.parse(this.body) })
      },
    }
    void handler({ method, url, headers }, res)
  })
}
