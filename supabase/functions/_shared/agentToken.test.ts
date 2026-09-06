import { describe, expect, it } from 'vitest';
import { agentClientId, bearerToken, decodeJwtPayload, isAgentToken } from './agentToken';

const b64url = (s: string) => btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const fakeJwt = (payload: Record<string, unknown>) =>
  `${b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))}.${b64url(JSON.stringify(payload))}.sig`;

describe('bearerToken', () => {
  it('strips the scheme case-insensitively and rejects other schemes', () => {
    expect(bearerToken('Bearer abc')).toBe('abc');
    expect(bearerToken('bearer   abc ')).toBe('abc');
    expect(bearerToken('Basic abc')).toBeNull();
    expect(bearerToken(null)).toBeNull();
    expect(bearerToken('Bearer ')).toBeNull();
  });
});

describe('decodeJwtPayload', () => {
  it('decodes base64url payloads and returns null for garbage', () => {
    expect(decodeJwtPayload(fakeJwt({ sub: 'u1', client_id: 'c1' }))).toEqual({ sub: 'u1', client_id: 'c1' });
    expect(decodeJwtPayload('not.a')).toBeNull();
    expect(decodeJwtPayload('a.!!!.c')).toBeNull();
  });
});

describe('agentClientId / isAgentToken', () => {
  it('detects the client_id claim that only OAuth-issued tokens carry', () => {
    expect(agentClientId(fakeJwt({ sub: 'u1', client_id: 'c1' }))).toBe('c1');
    expect(agentClientId(fakeJwt({ sub: 'u1' }))).toBeNull();
    expect(agentClientId(fakeJwt({ sub: 'u1', client_id: '' }))).toBeNull();
    expect(isAgentToken(fakeJwt({ client_id: 'c1' }))).toBe(true);
    expect(isAgentToken(fakeJwt({ sub: 'u1' }))).toBe(false);
    expect(isAgentToken(null)).toBe(false);
    expect(isAgentToken('garbage')).toBe(false);
  });
});
