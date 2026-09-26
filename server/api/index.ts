// Vercel serverless entry point. All /api/* requests are rewritten here
// (see vercel.json) and handled by the same Express app used locally.
import app from '../src/app';

export default app;
