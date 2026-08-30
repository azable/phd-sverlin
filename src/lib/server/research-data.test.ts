import { createHash } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import { pilotStudyV1 } from '$lib/shared/study/pilot-v1';

import { studyDefinitionsForEnrollments, verifyResearchResource } from './research-data';
import { participantPurgeConfirmation } from './research-data-lifecycle';

describe('research data verification', () => {
  it('requires an exact participant-specific purge confirmation', () => {
    expect(participantPurgeConfirmation('P-104')).toBe('DELETE P-104');
  });

  it('accepts bytes matching immutable resource metadata', () => {
    const bytes = Buffer.from('verified research resource');
    const digest = createHash('sha256').update(bytes).digest('hex');
    expect(() =>
      verifyResearchResource(bytes, {
        resourceId: `sha256-${digest}`,
        sha256: digest,
        byteLength: bytes.byteLength
      })
    ).not.toThrow();
  });

  it('rejects truncated or substituted resources', () => {
    const expected = createHash('sha256').update('expected').digest('hex');
    expect(() =>
      verifyResearchResource(Buffer.from('wrong'), {
        resourceId: `sha256-${expected}`,
        sha256: expected,
        byteLength: Buffer.byteLength('expected')
      })
    ).toThrow(/byte length|SHA-256/);
  });

  it('exports the exact registered protocol version used by enrollments once', () => {
    const enrollments = [
      { studyId: pilotStudyV1.id, studyVersion: pilotStudyV1.version },
      { studyId: pilotStudyV1.id, studyVersion: pilotStudyV1.version }
    ];
    expect(studyDefinitionsForEnrollments(enrollments)).toEqual([pilotStudyV1]);
  });
});
