import {
  bucket,
  defineRailway,
  github,
  postgres,
  preserve,
  project,
  ref,
  service
} from 'railway/iac';

const applicationRegion = 'asia-southeast1-eqsg3a';
// pg-boss expires a project command after 30 minutes by default (jobs.ts). Give a
// running worker one additional minute to finish its shutdown before Railway stops it.
const workerJobExpirySeconds = 30 * 60;
const workerShutdownMarginSeconds = 60;

export default defineRailway(() => {
  // Railway's GitHub source deploys main only after the required CI check succeeds.
  const source = github('azable/phd-sverlin', { branch: 'main', checkSuites: true });
  // The production database already owns a persistent volume in Amsterdam. Leaving
  // its region unmanaged avoids an unsafe cross-region volume move.
  const database = postgres('postgres');
  const resources = bucket('project-resources', { region: 'sin' });
  const sharedRuntime = {
    DATABASE_URL: database.env.DATABASE_URL,
    BUCKET: ref(resources, 'BUCKET'),
    ENDPOINT: ref(resources, 'ENDPOINT'),
    ACCESS_KEY_ID: ref(resources, 'ACCESS_KEY_ID'),
    SECRET_ACCESS_KEY: ref(resources, 'SECRET_ACCESS_KEY'),
    REGION: ref(resources, 'REGION'),
    SVERLIN_PROJECT_STORE: 'postgres'
  };

  const web = service('web', {
    source,
    build: { builder: 'DOCKERFILE', dockerfilePath: 'Dockerfile' },
    start: 'node build',
    preDeploy: 'node build-migrate/index.js',
    healthcheck: '/api/health/ready',
    healthcheckTimeout: 300,
    replicas: { [applicationRegion]: 1 },
    deploy: {
      // Match adapter-node's 30-second SHUTDOWN_TIMEOUT in the Dockerfile.
      drainingSeconds: 30,
      restartPolicyType: 'ON_FAILURE',
      restartPolicyMaxRetries: 10
    },
    env: {
      ...sharedRuntime,
      BETTER_AUTH_SECRET: preserve(),
      BETTER_AUTH_URL: preserve(),
      BETTER_AUTH_TRUSTED_ORIGINS: preserve(),
      SVERLIN_ADMIN_SETUP_TOKEN: preserve()
    }
  });

  const worker = service('worker', {
    source,
    build: { builder: 'DOCKERFILE', dockerfilePath: 'Dockerfile' },
    start: 'node build-worker/index.js',
    replicas: { [applicationRegion]: 1 },
    deploy: {
      drainingSeconds: workerJobExpirySeconds + workerShutdownMarginSeconds,
      restartPolicyType: 'ON_FAILURE',
      restartPolicyMaxRetries: 10,
      // The worker runs GHC plus the native solver; retain the existing 4 GiB ceiling.
      limitOverride: { containers: { memoryBytes: 4 * 1024 * 1024 * 1024 } }
    },
    env: {
      ...sharedRuntime,
      OPENAI_API_KEY: preserve(),
      OPENAI_MODEL: preserve(),
      CHATBOT_CONFIG: preserve()
    }
  });

  return project('phd-sverlin', { resources: [web, worker, database, resources] });
});
