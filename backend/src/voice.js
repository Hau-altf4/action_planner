import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { isAbsolute, join, resolve } from 'node:path';

const thuMucVietTts = process.env.VIETTTS_DIR
  ? resolve(process.env.VIETTTS_DIR)
  : '';
const tepTuDien = process.env.VIETTTS_LEXICON ||
  'assets/infore/lexicon.txt';
const lenhPython = process.env.VIETTTS_PYTHON ||
  (process.platform === 'win32' ? 'python' : 'python3');

export function daCauHinhGiongNoi() {
  return Boolean(thuMucVietTts);
}

function chayVietTts(vanBan, tepDauRa) {
  return new Promise((resolvePromise, reject) => {
    const duongDanTuDien = isAbsolute(tepTuDien)
      ? tepTuDien
      : join(thuMucVietTts, tepTuDien);
    const tienTrinh = spawn(
      lenhPython,
      [
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
      ],
      {
        cwd: thuMucVietTts,
        env: process.env,
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

export async function taoGiongNoi(vanBan) {
  if (!daCauHinhGiongNoi()) {
    const error = new Error(
      'Giọng nói chưa được cấu hình. Hãy đặt VIETTTS_DIR trong backend/.env.',
    );
    error.statusCode = 503;
    throw error;
  }

  const thuMucTam = await mkdtemp(join(tmpdir(), 'action-planner-tts-'));
  const tepDauRa = join(thuMucTam, 'giong-noi.wav');
  try {
    await chayVietTts(vanBan, tepDauRa);
    return await readFile(tepDauRa);
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
}
