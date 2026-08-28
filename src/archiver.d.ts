declare module 'archiver' {
  import { Transform } from 'node:stream';
  import type { ZlibOptions } from 'node:zlib';

  export class Archiver extends Transform {
    abort(): this;
    append(source: Buffer | string, data: { name: string }): this;
    finalize(): Promise<void>;
  }

  export class ZipArchive extends Archiver {
    constructor(options?: { zlib?: ZlibOptions });
  }
}
