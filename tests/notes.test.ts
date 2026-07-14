import request from 'supertest';
import { createApp } from '../src/app';

const app = createApp();

async function registerAndGetToken(email = 'notes@example.com') {
  const res = await request(app)
    .post('/api/auth/register')
    .send({ email, password: 'password123' });
  return res.body.token as string;
}

describe('notes CRUD', () => {
  it('creates, lists, updates and deletes a note', async () => {
    const token = await registerAndGetToken();
    const auth = { Authorization: `Bearer ${token}` };

    const created = await request(app)
      .post('/api/notes')
      .set(auth)
      .send({ title: 'First', content: 'Hello world' });
    expect(created.status).toBe(201);
    expect(created.body).toMatchObject({ title: 'First', content: 'Hello world' });

    const list = await request(app).get('/api/notes').set(auth);
    expect(list.status).toBe(200);
    expect(list.body).toHaveLength(1);

    const updated = await request(app)
      .patch(`/api/notes/${created.body.id}`)
      .set(auth)
      .send({ title: 'Renamed' });
    expect(updated.status).toBe(200);
    expect(updated.body.title).toBe('Renamed');

    const deleted = await request(app).delete(`/api/notes/${created.body.id}`).set(auth);
    expect(deleted.status).toBe(204);

    const listAfter = await request(app).get('/api/notes').set(auth);
    expect(listAfter.body).toHaveLength(0);
  });

  it('forbids reading another user notes', async () => {
    const tokenA = await registerAndGetToken('a@example.com');
    const tokenB = await registerAndGetToken('b@example.com');

    const created = await request(app)
      .post('/api/notes')
      .set('Authorization', `Bearer ${tokenA}`)
      .send({ title: 'Private', content: 'For A only' });

    const res = await request(app)
      .get(`/api/notes/${created.body.id}`)
      .set('Authorization', `Bearer ${tokenB}`);

    expect(res.status).toBe(403);
  });

  it('requires auth', async () => {
    const res = await request(app).get('/api/notes');
    expect(res.status).toBe(401);
  });
});
