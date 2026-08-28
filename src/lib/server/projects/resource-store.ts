/** Immutable compiler resource storage for local files and private Railway Buckets. */

import { createHash } from 'node:crypto';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

import {
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

import type { ProjectResourceBlob } from './repository';

export interface ProjectResourceStore {
  put(projectId: string, resource: ProjectResourceBlob): Promise<string>;
  get(pathname: string): Promise<Uint8Array>;
  downloadUrl(pathname: string): Promise<string>;
  deleteProject(projectId: string): Promise<void>;
}

class S3ProjectResourceStore implements ProjectResourceStore {
  readonly bucket = bucketConfiguration().bucket;
  readonly client = new S3Client(bucketConfiguration().client);

  async put(projectId: string, resource: ProjectResourceBlob): Promise<string> {
    assertBytes(resource);
    const pathname = resourcePathname(projectId, resource.id);
    try {
      await this.client.send(
        new PutObjectCommand({
          Bucket: this.bucket,
          Key: pathname,
          Body: Buffer.from(resource.bytes),
          ContentType: resource.mediaType,
          CacheControl: 'private, max-age=2592000, immutable',
          Metadata: { sha256: resource.sha256 },
          IfNoneMatch: '*'
        })
      );
    } catch (cause) {
      if (!isPreconditionFailure(cause)) throw cause;
      const existing = await this.client.send(
        new HeadObjectCommand({ Bucket: this.bucket, Key: pathname })
      );
      if (
        existing.ContentLength !== resource.byteLength ||
        existing.Metadata?.sha256 !== resource.sha256
      ) {
        throw new Error(`Stored resource ${resource.id} does not match its content address.`);
      }
    }
    return pathname;
  }

  async get(pathname: string): Promise<Uint8Array> {
    const result = await this.client.send(
      new GetObjectCommand({ Bucket: this.bucket, Key: pathname })
    );
    if (!result.Body) throw new Error('Resource not found.');
    return result.Body.transformToByteArray();
  }

  async downloadUrl(pathname: string): Promise<string> {
    return getSignedUrl(this.client, new GetObjectCommand({ Bucket: this.bucket, Key: pathname }), {
      expiresIn: 5 * 60
    });
  }

  async deleteProject(projectId: string): Promise<void> {
    let continuationToken: string | undefined;
    do {
      const page = await this.client.send(
        new ListObjectsV2Command({
          Bucket: this.bucket,
          Prefix: `projects/${projectId}/`,
          ContinuationToken: continuationToken
        })
      );
      const objects = (page.Contents ?? []).flatMap(({ Key }) => (Key ? [{ Key }] : []));
      if (objects.length) {
        const deletion = await this.client.send(
          new DeleteObjectsCommand({ Bucket: this.bucket, Delete: { Objects: objects } })
        );
        if (deletion.Errors?.length) {
          throw new Error(
            `Could not delete ${deletion.Errors.length} project resource object(s) from the Bucket.`
          );
        }
      }
      continuationToken = page.IsTruncated ? page.NextContinuationToken : undefined;
    } while (continuationToken);
  }
}

class FileProjectResourceStore implements ProjectResourceStore {
  readonly root = path.resolve(
    process.cwd(),
    process.env.SVERLIN_RESOURCE_DIR ?? '.local/state/sverlin/resources'
  );

  async put(projectId: string, resource: ProjectResourceBlob): Promise<string> {
    assertBytes(resource);
    const pathname = resourcePathname(projectId, resource.id);
    const destination = this.destination(pathname);
    await mkdir(path.dirname(destination), { recursive: true });
    try {
      await writeFile(destination, resource.bytes, { flag: 'wx' });
    } catch (cause) {
      if (!isAlreadyExists(cause)) throw cause;
      const existing = await readFile(destination);
      if (!existing.equals(Buffer.from(resource.bytes))) {
        throw new Error(`Stored resource ${resource.id} does not match its content address.`);
      }
    }
    return pathname;
  }

  async get(pathname: string): Promise<Uint8Array> {
    return readFile(this.destination(pathname));
  }

  async downloadUrl(_pathname: string): Promise<string> {
    throw new Error('Local resources are served through the authenticated application route.');
  }

  async deleteProject(projectId: string): Promise<void> {
    await rm(this.destination(`projects/${projectId}`), { recursive: true, force: true });
  }

  private destination(pathname: string) {
    const destination = path.resolve(this.root, pathname);
    if (!destination.startsWith(`${this.root}${path.sep}`))
      throw new Error('Invalid resource path.');
    return destination;
  }
}

export const railwayBucketConfigured = hasBucketConfiguration();

export const projectResourceStore: ProjectResourceStore = railwayBucketConfigured
  ? new S3ProjectResourceStore()
  : new FileProjectResourceStore();

/** Fail closed when a Railway service is missing its durable Bucket references. */
export function validateProjectResourceStorageConfiguration(): void {
  if (process.env.RAILWAY_ENVIRONMENT_ID && !railwayBucketConfigured) {
    throw new Error('Railway Bucket credentials are required for durable project resources.');
  }
}

function bucketConfiguration() {
  const bucket = process.env.SVERLIN_BUCKET_NAME ?? process.env.BUCKET;
  const endpoint = process.env.SVERLIN_BUCKET_ENDPOINT ?? process.env.ENDPOINT;
  const accessKeyId =
    process.env.SVERLIN_BUCKET_ACCESS_KEY_ID ??
    process.env.ACCESS_KEY_ID ??
    process.env.AWS_ACCESS_KEY_ID;
  const secretAccessKey =
    process.env.SVERLIN_BUCKET_SECRET_ACCESS_KEY ??
    process.env.SECRET_ACCESS_KEY ??
    process.env.AWS_SECRET_ACCESS_KEY;
  const region =
    process.env.SVERLIN_BUCKET_REGION ??
    process.env.REGION ??
    process.env.AWS_DEFAULT_REGION ??
    'auto';
  if (!bucket || !endpoint || !accessKeyId || !secretAccessKey) {
    throw new Error('Railway Bucket credentials are incomplete.');
  }
  return {
    bucket,
    client: {
      endpoint,
      region,
      credentials: { accessKeyId, secretAccessKey },
      forcePathStyle: process.env.SVERLIN_BUCKET_FORCE_PATH_STYLE === 'true'
    }
  };
}

function hasBucketConfiguration() {
  return Boolean(
    (process.env.SVERLIN_BUCKET_NAME ?? process.env.BUCKET) &&
    (process.env.SVERLIN_BUCKET_ENDPOINT ?? process.env.ENDPOINT) &&
    (process.env.SVERLIN_BUCKET_ACCESS_KEY_ID ??
      process.env.ACCESS_KEY_ID ??
      process.env.AWS_ACCESS_KEY_ID) &&
    (process.env.SVERLIN_BUCKET_SECRET_ACCESS_KEY ??
      process.env.SECRET_ACCESS_KEY ??
      process.env.AWS_SECRET_ACCESS_KEY)
  );
}

function resourcePathname(projectId: string, resourceId: string) {
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$/.test(projectId)) throw new Error('Invalid project ID.');
  if (!/^sha256-[a-f0-9]{64}$/.test(resourceId)) throw new Error('Invalid resource ID.');
  return `projects/${projectId}/${resourceId}`;
}

function assertBytes(resource: ProjectResourceBlob) {
  if (resource.bytes.byteLength !== resource.byteLength)
    throw new Error('Resource length mismatch.');
  const digest = createHash('sha256').update(resource.bytes).digest('hex');
  if (digest !== resource.sha256 || resource.id !== `sha256-${digest}`) {
    throw new Error('Resource content hash mismatch.');
  }
}

function isPreconditionFailure(cause: unknown) {
  return (
    cause instanceof Error &&
    '$metadata' in cause &&
    typeof cause.$metadata === 'object' &&
    cause.$metadata !== null &&
    'httpStatusCode' in cause.$metadata &&
    cause.$metadata.httpStatusCode === 412
  );
}

function isAlreadyExists(cause: unknown): cause is NodeJS.ErrnoException {
  return cause instanceof Error && 'code' in cause && cause.code === 'EEXIST';
}
