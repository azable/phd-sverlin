import { bucket, defineRailway, github, group, postgres, project, ref, service } from 'railway/iac';

const applicationRegion = 'asia-southeast1-eqsg3a';
const workerJobExpirySeconds = 30 * 60;
const workerShutdownMarginSeconds = 60;

export default defineRailway((ctx) => {
  // Both environments build main commits after GitHub checks pass. Railway automatically
  // deploys staging; production auto-deploys are disabled in the dashboard.
  const source = github('azable/phd-sverlin', { branch: 'main', checkSuites: true });
  const database = postgres('postgres', { region: applicationRegion });
  const resources = bucket('project-resources', { region: 'sin' });
  const sharedRuntime = {
    DATABASE_URL: database.env.DATABASE_URL,
    BUCKET: ref(resources, 'BUCKET'),
    ENDPOINT: ref(resources, 'ENDPOINT'),
    ACCESS_KEY_ID: ref(resources, 'ACCESS_KEY_ID'),
    SECRET_ACCESS_KEY: ref(resources, 'SECRET_ACCESS_KEY'),
    REGION: ref(resources, 'REGION')
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
      drainingSeconds: workerJobExpirySeconds + workerShutdownMarginSeconds,
      restartPolicyType: 'ON_FAILURE',
      restartPolicyMaxRetries: 10,
      limitOverride: { containers: { memoryBytes: 4 * 1024 * 1024 * 1024 } }
    },
    env: {
      ...sharedRuntime,
      OPENAI_API_KEY: ctx.shared.OPENAI_API_KEY,
      OPENAI_MODEL: ctx.shared.OPENAI_MODEL,
      CHATBOT_CONFIG: ctx.shared.CHATBOT_CONFIG
    }
  });

  return project('phd-sverlin', {
    resources: [
      ...group('Application', [web, worker], { color: '#7c3aed' }),
      ...group('Data', [database, resources], { color: '#0891b2' })
    ]
  });
});
