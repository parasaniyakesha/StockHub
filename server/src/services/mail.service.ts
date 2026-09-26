import nodemailer from 'nodemailer';
import { env } from '../config/env';
import { logger } from '../utils/logger';

export const mailConfigured = () => Boolean(env.SMTP_HOST);

let transporter: nodemailer.Transporter | null = null;

function getTransporter() {
  if (!transporter) {
    transporter = nodemailer.createTransport({
      host: env.SMTP_HOST,
      port: env.SMTP_PORT,
      secure: env.SMTP_PORT === 465,
      auth: env.SMTP_USER ? { user: env.SMTP_USER, pass: env.SMTP_PASSWORD } : undefined,
    });
  }
  return transporter;
}

export async function sendMail(to: string, subject: string, text: string) {
  if (!mailConfigured()) {
    logger.warn({ subject }, 'SMTP is not configured - email not sent');
    return false;
  }
  try {
    await getTransporter().sendMail({ from: env.SMTP_FROM, to, subject, text });
    return true;
  } catch (err) {
    logger.error({ err, subject }, 'Failed to send email');
    return false;
  }
}
