import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { delimiter, isAbsolute, join, resolve } from 'node:path';

const thuMucVietTts = process.env.VIETTTS_DIR
  ? resolve(process.env.VIETTTS_DIR)
  : '';
const boMayGiongNoi = (process.env.VOICE_ENGINE || 'viettts').toLowerCase();
const tepTuDien = process.env.VIETTTS_LEXICON ||
  'assets/infore/lexicon.txt';
const lenhPython = process.env.VIETTTS_PYTHON ||
  (process.platform === 'win32' ? 'python' : 'python3');
const thuMucCache = resolve(
  process.env.VOICE_CACHE_DIR || join(process.cwd(), 'cache', 'voice'),
);
const dangTao = new Map();

export function daCauHinhGiongNoi() {
  return boMayGiongNoi !== 'device' && Boolean(thuMucVietTts);
}

export function thongTinGiongNoi() {
  return {
    engine: boMayGiongNoi,
    configured: daCauHinhGiongNoi(),
    customizable: boMayGiongNoi === 'vietvoice',
  };
}

function chayVietTts(vanBan, tepDauRa, tuyChon) {
  return new Promise((resolvePromise, reject) => {
    const duongDanTuDien = isAbsolute(tepTuDien)
      ? tepTuDien
      : join(thuMucVietTts, tepTuDien);
    const thamSo = boMayGiongNoi === 'vietvoice'
      ? [
        '-m',
        'vietvoicetts',
        vanBan,
        tepDauRa,
        '--gender',
        tuyChon.gender,
        '--area',
        tuyChon.region,
        ...(process.env.VIETVOICE_MODEL_CACHE
          ? ['--model-cache-dir', process.env.VIETVOICE_MODEL_CACHE]
          : []),
        '--nfe-step',
        String(Math.max(2, Number(process.env.VIETVOICE_NFE_STEP) || 2)),
        '--speed',
        String(Math.max(0.8, Number(process.env.VIETVOICE_SPEED) || 1.15)),
      ]
      : [
        '-m',
        'vietTTS.synthesizer',
        '--text',
        vanBan,
        '--output',
        tepDauRa,
        '--lexicon-file',
        duongDanTuDien,
        '--silence-duration',
        '0.2',
      ];
    const tienTrinh = spawn(
      lenhPython,
      thamSo,
      {
        cwd: thuMucVietTts,
        env: {
          ...process.env,
          PATH: process.env.VIETVOICE_FFMPEG_DIR
            ? `${process.env.VIETVOICE_FFMPEG_DIR}${delimiter}${process.env.PATH || process.env.Path || ''}`
            : process.env.PATH || process.env.Path,
          PYTHONUTF8: '1',
          PYTHONIOENCODING: 'utf-8',
        },
        windowsHide: true,
        shell: false,
      },
    );

    let loi = '';
    tienTrinh.stderr.setEncoding('utf8');
    tienTrinh.stderr.on('data', (duLieu) => {
      loi = `${loi}${duLieu}`.slice(-4000);
    });
    let daKetThuc = false;
    let boDemGio;
    const ketThuc = (callback) => {
      if (daKetThuc) return;
      daKetThuc = true;
      clearTimeout(boDemGio);
      callback();
    };
    tienTrinh.on('error', (error) => ketThuc(() => reject(error)));
    tienTrinh.on('close', (maThoat) => {
      ketThuc(() => {
        if (maThoat === 0) return resolvePromise();
        reject(new Error(
          loi.trim() || `vietTTS kết thúc với mã lỗi ${maThoat}.`,
        ));
      });
    });

    const gioiHan = Math.max(
      10_000,
      Number(process.env.VIETTTS_TIMEOUT_MS) || 120_000,
    );
    boDemGio = setTimeout(() => {
      tienTrinh.kill();
      ketThuc(() => reject(
        new Error('vietTTS xử lý quá thời gian cho phép.'),
      ));
    }, gioiHan).unref();
  });
}

export async function taoGiongNoi(
  vanBan,
  { gender = 'female', region = 'northern' } = {},
) {
  if (!daCauHinhGiongNoi()) {
    const error = new Error(
      'Giọng nói chưa được cấu hình. Hãy đặt VIETTTS_DIR trong backend/.env.',
    );
    error.statusCode = 503;
    throw error;
  }

  const cacheKey = createHash('sha256')
    .update([
      boMayGiongNoi,
      gender,
      region,
      process.env.VIETVOICE_NFE_STEP || '2',
      process.env.VIETVOICE_SPEED || '1.15',
      vanBan,
    ].join('\u0000'))
    .digest('hex');
  const tepCache = join(thuMucCache, `${cacheKey}.wav`);
  try {
    return await readFile(tepCache);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }

  if (dangTao.has(cacheKey)) return dangTao.get(cacheKey);
  const congViec = (async () => {
    const thuMucTam = await mkdtemp(join(tmpdir(), 'action-planner-tts-'));
    const tepDauRa = join(thuMucTam, 'giong-noi.wav');
    try {
      await chayVietTts(vanBan, tepDauRa, { gender, region });
      const audio = await readFile(tepDauRa);
      await mkdir(thuMucCache, { recursive: true });
      await writeFile(tepCache, audio);
      return audio;
    } catch (cause) {
      const error = new Error(
        `Không thể tạo giọng nói tiếng Việt: ${cause.message}`,
        { cause },
      );
      error.statusCode = cause.statusCode || 500;
      throw error;
    } finally {
      await rm(thuMucTam, { recursive: true, force: true });
    }
  })();
  dangTao.set(cacheKey, congViec);
  try {
    return await congViec;
  } finally {
    dangTao.delete(cacheKey);
  }
}
