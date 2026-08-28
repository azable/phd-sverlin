import { bucket, defineRailway, github, group, postgres, project, ref, service } from 'railway/iac';

const applicationRegion = 'asia-southeast1-eqsg3a';
const source = github('azable/phd-sverlin', { branch: 'main' });

export default defineRailway((ctx) => {
  const database = postgres('postgres', { region: applicationRegion });
  const resources = bucket('project-resources', { region: 'sin' });
  const sharedRuntime = {
    DATABASE_URL: database.env.DATABASE_URL,
    BUCKET: ref(resources, 'BUCKET'),
    ENDPOINT: ref(resources, 'ENDPOINT'),
    ACCESS_KEY_ID: ref(resources, 'ACCESS_KEY_ID'),
    SECRET_ACCESS_KEY: ref(resources, 'SECRET_ACCESS_KEY'),
    REGION: ref(resources, 'REGION'),
    SVERLIN_PROJECT_STORE: 'postgres',
    SVERLIN_DATABASE_POOL_SIZE: '5',
    SVERLIN_JOB_EXPIRE_SECONDS: '1800',
    SVERLIN_JOB_HEARTBEAT_SECONDS: '60'
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
      drainingSeconds: 30,
      restartPolicyType: 'ON_FAILURE',
      restartPolicyMaxRetries: 10
    },
    env: {
      ...sharedRuntime,
      BETTER_AUTH_SECRET: ctx.shared.BETTER_AUTH_SECRET,
      BETTER_AUTH_URL: ctx.shared.BETTER_AUTH_URL,
      BETTER_AUTH_TRUSTED_ORIGINS: ctx.shared.BETTER_AUTH_URL,
      SVERLIN_ADMIN_SETUP_TOKEN: ctx.shared.SVERLIN_ADMIN_SETUP_TOKEN
    }
  });

  const worker = service('worker', {
    source,
    build: { builder: 'DOCKERFILE', dockerfilePath: 'Dockerfile' },
    start: 'node build-worker/index.js',
    replicas: { [applicationRegion]: 1 },
    deploy: {
      drainingSeconds: 1860,
      restartPolicyType: 'ON_FAILURE',
      restartPolicyMaxRetries: 10,
      limitOverride: { containers: { memoryBytes: 4 * 1024 * 1024 * 1024 } }
    },
    env: {
      ...sharedRuntime,
      OPENAI_API_KEY: ctx.shared.OPENAI_API_KEY,
      SVERLIN_COMPILE_TIMEOUT_MS: '300000',
      CHATBOT_REQUEST_TIMEOUT_MS: '180000'
    }
  });

  return project('phd-sverlin', {
    resources: [
      ...group('Application', [web, worker], { color: '#7c3aed' }),
      ...group('Data', [database, resources], { color: '#0891b2' })
    ]
  });
});
