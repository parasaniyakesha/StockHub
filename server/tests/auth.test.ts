import { beforeAll, describe, expect, it } from 'vitest';
import { api, bearer, buildFixture, Fixture, PASSWORD } from './helpers';
import { prisma } from '../src/utils/prisma';

let f: Fixture;
beforeAll(async () => {
  f = await buildFixture();
});

describe('authentication', () => {
  it('logs in and returns tokens and a safe user payload', async () => {
    const res = await api().post('/api/auth/login').send({ email: 'ADMIN@test.local', password: PASSWORD });
    expect(res.status).toBe(200);
    expect(res.body.data.accessToken).toBeTypeOf('string');
    expect(res.body.data.refreshToken).toBeTypeOf('string');
    expect(res.body.data.user).toMatchObject({ email: 'admin@test.local', role: 'ADMIN', storeId: null });
    expect(res.body.data.user.passwordHash).toBeUndefined();
  });

  it('rejects a wrong password with a generic message', async () => {
    const res = await api().post('/api/auth/login').send({ email: 'admin@test.local', password: 'Wrong@123' });
    expect(res.status).toBe(401);
    expect(res.body).toMatchObject({ success: false, code: 'UNAUTHORIZED', message: 'Invalid email or password' });
    const unknown = await api().post('/api/auth/login').send({ email: 'nobody@test.local', password: 'Wrong@123' });
    expect(unknown.body.message).toBe(res.body.message);
  });

  it('validates login input', async () => {
    const res = await api().post('/api/auth/login').send({ email: 'not-an-email' });
    expect(res.status).toBe(422);
    expect(res.body.code).toBe('VALIDATION_ERROR');
    expect(res.body.errors.map((e: { field: string }) => e.field)).toEqual(expect.arrayContaining(['email', 'password']));
  });

  it('requires a token for protected routes', async () => {
    expect((await api().get('/api/auth/me')).status).toBe(401);
    expect((await api().get('/api/auth/me').set({ Authorization: 'Bearer garbage' })).status).toBe(401);
  });

  it('returns the current user with permissions and managed stores', async () => {
    const res = await api().get('/api/auth/me').set(bearer(f.tokens.m1));
    expect(res.status).toBe(200);
    expect(res.body.data.role).toBe('MANAGER');
    expect(res.body.data.managedStores.map((s: { code: string }) => s.code).sort()).toEqual(['STA', 'STB']);
    expect(res.body.data.permissions).toContain('requests.approve');
  });

  it('rotates refresh tokens and revokes all sessions when a used token is replayed', async () => {
    const login = await api().post('/api/auth/login').send({ email: 'b@test.local', password: PASSWORD });
    const first = login.body.data.refreshToken;
    const refreshed = await api().post('/api/auth/refresh').send({ refreshToken: first });
    expect(refreshed.status).toBe(200);
    const second = refreshed.body.data.refreshToken;
    expect(second).not.toBe(first);

    // Replay of the rotated token = theft signal.
    const replay = await api().post('/api/auth/refresh').send({ refreshToken: first });
    expect(replay.status).toBe(401);
    // ...which also killed the legitimate newer token.
    expect((await api().post('/api/auth/refresh').send({ refreshToken: second })).status).toBe(401);
  });

  it('logout revokes the refresh token', async () => {
    const login = await api().post('/api/auth/login').send({ email: 'c@test.local', password: PASSWORD });
    const { accessToken, refreshToken } = login.body.data;
    expect((await api().post('/api/auth/logout').set(bearer(accessToken)).send({ refreshToken })).status).toBe(200);
    expect((await api().post('/api/auth/refresh').send({ refreshToken })).status).toBe(401);
  });

  it('supports forgot/reset password and invalidates old sessions', async () => {
    const oldToken = (await api().post('/api/auth/login').send({ email: 'a@test.local', password: PASSWORD })).body.data.accessToken;
    const forgot = await api().post('/api/auth/forgot-password').send({ email: 'a@test.local' });
    expect(forgot.status).toBe(200);
    const token = forgot.body.data.devResetToken;
    expect(token).toBeTypeOf('string');

    // Same response shape for unknown emails (no enumeration).
    const unknown = await api().post('/api/auth/forgot-password').send({ email: 'ghost@test.local' });
    expect(unknown.body.message).toBe(forgot.body.message);

    expect((await api().post('/api/auth/reset-password').send({ token, newPassword: 'weak' })).status).toBe(422);
    const reset = await api().post('/api/auth/reset-password').send({ token, newPassword: 'NewPass@123' });
    expect(reset.status).toBe(200);
    expect((await api().post('/api/auth/reset-password').send({ token, newPassword: 'Another@123' })).status).toBe(400);

    expect((await api().get('/api/auth/me').set(bearer(oldToken))).status).toBe(401);
    expect((await api().post('/api/auth/login').send({ email: 'a@test.local', password: 'NewPass@123' })).status).toBe(200);
    // restore for other assertions
    await prisma.user.update({ where: { email: 'a@test.local' }, data: { passwordHash: (await prisma.user.findUniqueOrThrow({ where: { email: 'b@test.local' } })).passwordHash } });
  });

  it('blocks inactive users immediately, even with a valid access token', async () => {
    const token = (await api().post('/api/auth/login').send({ email: 'c@test.local', password: PASSWORD })).body.data.accessToken;
    const res = await api().patch(`/api/users/${f.userC.id}/status`).set(bearer(f.tokens.admin)).send({ status: 'INACTIVE' });
    expect(res.status).toBe(200);
    expect((await api().get('/api/auth/me').set(bearer(token))).status).toBe(401);
    const login = await api().post('/api/auth/login').send({ email: 'c@test.local', password: PASSWORD });
    expect(login.status).toBe(403);
    await api().patch(`/api/users/${f.userC.id}/status`).set(bearer(f.tokens.admin)).send({ status: 'ACTIVE' });
  });

  it('admin cannot deactivate their own account', async () => {
    const res = await api().patch(`/api/users/${f.admin.id}/status`).set(bearer(f.tokens.admin)).send({ status: 'INACTIVE' });
    expect(res.status).toBe(400);
  });

  it('writes audit entries for logins', async () => {
    expect(await prisma.auditLog.count({ where: { action: 'LOGIN' } })).toBeGreaterThan(0);
  });
});
