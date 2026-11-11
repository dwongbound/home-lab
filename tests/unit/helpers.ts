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
  body = '',
): Promise<FakeResponse> {
  return new Promise((resolve) => {
    const res = {
      statusCode: 200,
      headers: {} as Record<string, string>,
      body: '',
      setHeader(name: string, value: string) { this.headers[name] = value },
      // Streamed answers (the chat) set status and headers at once, then write in pieces.
      writeHead(status: number, headers: Record<string, string> = {}) { this.statusCode = status; Object.assign(this.headers, headers) },
      write(chunk: string) { this.body += String(chunk) },
      end(chunk = '') {
        this.body += String(chunk)
        resolve({ statusCode: this.statusCode, headers: this.headers, body: this.body, json: () => JSON.parse(this.body) })
      },
    }
    // The request is an async iterable of body chunks, like Node's.
    const req = { method, url, headers, async *[Symbol.asyncIterator]() { if (body) yield body } }
    void handler(req, res)
  })
}
