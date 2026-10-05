import 'dotenv/config';
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
  randomUUID,
} from 'node:crypto';
import { availableParallelism } from 'node:os';

import bcrypt from 'bcryptjs';
import cors from 'cors';
import express from 'express';
import jwt from 'jsonwebtoken';
import { MongoClient, ObjectId } from 'mongodb';

const app = express();
app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.use((req, res, next) => {
  if (!req.path.startsWith('/api/auth/')) return next();
  const startedAt = Date.now();
  res.on('finish', () => {
    console.log(
      `[auth] ${req.method} ${req.path} ${res.statusCode} ${Date.now() - startedAt}ms`,
    );
  });
  next();
});

const mongoUri =
  process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/action_planner';
const mongoClient = new MongoClient(mongoUri);
const database = mongoClient.db(process.env.MONGODB_DB || 'action_planner');
const users = database.collection('users');
const tasks = database.collection('tasks');
const userSettings = database.collection('user_settings');
const appSettings = database.collection('app_settings');
const feedback = database.collection('feedback');
const aiUsage = database.collection('ai_usage');
const supportedProviders = new Set(['ollama', 'openai', 'gemini', 'anthropic']);
const defaultProvider = (process.env.AI_PROVIDER || 'ollama').toLowerCase();

const asyncRoute = (handler) => (req, res, next) =>
  Promise.resolve(handler(req, res, next)).catch(next);

function createToken(user) {
  return jwt.sign(
    { sub: user._id.toString(), email: user.email, role: user.role || 'user' },
    process.env.JWT_SECRET,
    { expiresIn: '7d' },
  );
}

function auth(req, res, next) {
  const token = req.headers.authorization?.replace(/^Bearer\s+/i, '');
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    req.user = { ...payload, id: new ObjectId(payload.sub) };
    next();
  } catch {
    res.status(401).json({ message: 'Phiên đăng nhập không hợp lệ.' });
  }
}

function adminOnly(req, res, next) {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Bạn không có quyền quản trị.' });
  }
  next();
}

function objectId(value) {
  return ObjectId.isValid(value) ? new ObjectId(value) : null;
}

function mapUser(user) {
  return {
    user_id: user._id.toString(),
    full_name: user.fullName,
    email: user.email,
    role: user.role || 'user',
    createdAt: user.createdAt,
    lastActiveAt: user.lastActiveAt,
  };
}

function encryptionKey() {
  return createHash('sha256')
    .update(process.env.API_KEY_ENCRYPTION_SECRET || process.env.JWT_SECRET)
    .digest();
}

function encryptSecret(value) {
  if (!value) return null;
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  return [iv, cipher.getAuthTag(), encrypted]
    .map((part) => part.toString('base64url'))
    .join('.');
}

function decryptSecret(value) {
  if (!value) return '';
  try {
    const [iv, tag, encrypted] = value.split('.').map((part) =>
      Buffer.from(part, 'base64url'),
    );
    const decipher = createDecipheriv('aes-256-gcm', encryptionKey(), iv);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString(
      'utf8',
    );
  } catch {
    return '';
  }
}

function envAiConfig() {
  const provider = supportedProviders.has(defaultProvider)
    ? defaultProvider
    : 'ollama';
  const byProvider = {
    ollama: {
      model: process.env.OLLAMA_MODEL || 'qwen3:1.7b',
      baseUrl: process.env.OLLAMA_BASE_URL || 'http://127.0.0.1:11434',
      apiKey: '',
    },
    openai: {
      model: process.env.OPENAI_MODEL || 'gpt-5.4-mini',
      baseUrl: 'https://api.openai.com',
      apiKey: process.env.OPENAI_API_KEY || '',
    },
    gemini: {
      model: process.env.GEMINI_MODEL || 'gemini-2.5-flash',
      baseUrl: 'https://generativelanguage.googleapis.com',
      apiKey: process.env.GEMINI_API_KEY || '',
    },
    anthropic: {
      model: process.env.ANTHROPIC_MODEL || 'claude-sonnet-4-5',
      baseUrl: 'https://api.anthropic.com',
      apiKey: process.env.ANTHROPIC_API_KEY || '',
    },
  };
  return { provider, ...byProvider[provider], source: 'environment' };
}

async function resolveAiConfig(userId) {
  const personal = userId
    ? await userSettings.findOne({ userId, customAiEnabled: true })
    : null;
  if (personal?.provider) {
    return {
      provider: personal.provider,
      model: personal.model,
      baseUrl: personal.baseUrl,
      apiKey: decryptSecret(personal.encryptedApiKey),
      source: 'personal',
    };
  }
  const savedDefault = await appSettings.findOne({ _id: 'default-ai' });
  if (savedDefault?.provider) {
    return {
      provider: savedDefault.provider,
      model: savedDefault.model,
      baseUrl: savedDefault.baseUrl,
      apiKey: decryptSecret(savedDefault.encryptedApiKey),
      source: 'admin',
    };
  }
  return envAiConfig();
}

function publicAiConfig(config, customAiEnabled = false) {
  return {
    provider: config.provider,
    model: config.model || '',
    baseUrl: config.baseUrl || '',
    customAiEnabled,
    hasApiKey: Boolean(config.apiKey || config.encryptedApiKey),
    source: config.source,
  };
}

function validateAiSettings(body) {
  const provider = String(body.provider || '').toLowerCase();
  if (!supportedProviders.has(provider)) {
    const error = new Error('Nhà cung cấp AI không được hỗ trợ.');
    error.statusCode = 400;
    throw error;
  }
  const baseUrl = String(body.baseUrl || '').trim().replace(/\/$/, '');
  if (baseUrl && !/^https?:\/\//i.test(baseUrl)) {
    const error = new Error('Địa chỉ máy chủ AI phải bắt đầu bằng http:// hoặc https://.');
    error.statusCode = 400;
    throw error;
  }
  return {
    provider,
    model: String(body.model || '').trim(),
    baseUrl,
  };
}

function mapTask(task) {
  return {
    id: task._id.toString(),
    title: task.title,
    description: task.description || '',
    category: task.category || 'Cá nhân',
    priority: task.priority,
    status: task.status,
    estimatedMinutes: task.estimatedMinutes,
    deadline: task.deadline,
    scheduledStart: task.scheduledStart || null,
    steps: task.steps || [],
    aiSuggestion: task.aiSuggestion || null,
  };
}

async function orderedUserTasks(userId) {
  const documents = await tasks.find({ userId }).toArray();
  return documents.sort((left, right) => {
    const completed = Number(left.status === 'completed') -
      Number(right.status === 'completed');
    if (completed !== 0) return completed;
    const planOrder = (left.planOrder ?? Number.MAX_SAFE_INTEGER) -
      (right.planOrder ?? Number.MAX_SAFE_INTEGER);
    return planOrder || new Date(left.deadline) - new Date(right.deadline);
  });
}

function taskFields(body) {
  const deadline = new Date(body.deadline);
  const scheduledStart = body.scheduledStart
    ? new Date(body.scheduledStart)
    : null;
  if (!body.title?.trim() || Number.isNaN(deadline.getTime())) {
    const error = new Error('Tiêu đề hoặc thời hạn công việc không hợp lệ.');
    error.statusCode = 400;
    throw error;
  }
  if (scheduledStart && Number.isNaN(scheduledStart.getTime())) {
    const error = new Error('Giờ bắt đầu trong lịch không hợp lệ.');
    error.statusCode = 400;
    throw error;
  }

  return {
    title: body.title.trim(),
    description: String(body.description || ''),
    category: String(body.category || 'Cá nhân'),
    priority: ['low', 'medium', 'high', 'urgent'].includes(body.priority)
      ? body.priority
      : 'medium',
    status: ['pending', 'inProgress', 'completed'].includes(body.status)
      ? body.status
      : 'pending',
    estimatedMinutes: Math.max(1, Number(body.estimatedMinutes) || 30),
    deadline,
    scheduledStart,
    steps: (Array.isArray(body.steps) ? body.steps : []).map((step) => ({
      id: String(step.id || randomUUID()),
      title: String(step.title || '').trim(),
      status: step.status === 'completed' ? 'completed' : 'pending',
    })),
    aiSuggestion: body.aiSuggestion ? String(body.aiSuggestion) : null,
  };
}

function parseAiJson(output) {
  const cleaned = String(output || '')
    .trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/, '');
  try {
    return JSON.parse(cleaned);
  } catch {
    const start = cleaned.indexOf('{');
    const end = cleaned.lastIndexOf('}');
    if (start >= 0 && end > start) return JSON.parse(cleaned.slice(start, end + 1));
    throw new Error('AI trả về dữ liệu không đúng định dạng JSON.');
  }
}

function hasExplicitOrderNote(task) {
  const note = String(task?.description || '').toLocaleLowerCase('vi');
  return /(?:làm|xếp|sắp xếp|thực hiện).{0,30}(?:trước|đầu tiên)|(?:ưu tiên|nên).{0,35}(?:trước|đầu tiên)/i.test(
    note,
  );
}

function normalizedVietnamese(value) {
  return String(value || '')
    .toLocaleLowerCase('vi')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/đ/g, 'd');
}

function taskMentionedInFeedback(task, feedback) {
  const title = normalizedVietnamese(task.title);
  if (title.length >= 4 && feedback.includes(title)) return true;
  const meaningfulWords = title
    .split(/[^a-z0-9]+/)
    .filter((word) => word.length >= 4);
  return meaningfulWords.length > 0 &&
    meaningfulWords.filter((word) => feedback.includes(word)).length >=
      Math.min(2, meaningfulWords.length);
}

app.get(
  '/health',
  asyncRoute(async (_req, res) => {
    await database.command({ ping: 1 });
    const config = await resolveAiConfig(null);
    res.json({
      status: 'ok',
      database: 'connected',
      databaseName: database.databaseName,
      ai: config.provider === 'ollama' || config.apiKey
        ? 'configured'
        : 'not_configured',
      aiProvider: config.provider,
      aiModel: config.model,
    });
  }),
);

app.post(
  '/api/auth/register',
  asyncRoute(async (req, res) => {
    const fullName = String(req.body.fullName || '').trim();
    const email = String(req.body.email || '').trim().toLowerCase();
    const password = String(req.body.password || '');
    if (!fullName || !email || password.length < 6) {
      return res
        .status(400)
        .json({ message: 'Thông tin đăng ký chưa hợp lệ.' });
    }

    const user = {
      fullName,
      email,
      passwordHash: await bcrypt.hash(password, 12),
      role: email === String(process.env.ADMIN_EMAIL || '').toLowerCase()
        ? 'admin'
        : 'user',
      createdAt: new Date(),
      updatedAt: new Date(),
      lastActiveAt: new Date(),
    };
    const result = await users.insertOne(user);
    user._id = result.insertedId;
    res.status(201).json({ user: mapUser(user), token: createToken(user) });
  }),
);

app.post(
  '/api/auth/login',
  asyncRoute(async (req, res) => {
    const email = String(req.body.email || '').trim().toLowerCase();
    const user = await users.findOne({ email });
    if (
      !user ||
      !(await bcrypt.compare(String(req.body.password || ''), user.passwordHash))
    ) {
      return res.status(401).json({ message: 'Email hoặc mật khẩu không đúng.' });
    }
    await users.updateOne(
      { _id: user._id },
      { $set: { lastActiveAt: new Date() } },
    );
    res.json({ user: mapUser(user), token: createToken(user) });
  }),
);

app.get(
  '/api/auth/me',
  auth,
  asyncRoute(async (req, res) => {
    const user = await users.findOne({ _id: req.user.id });
    if (!user) return res.status(404).json({ message: 'Tài khoản không tồn tại.' });
    res.json(mapUser(user));
  }),
);

app.get(
  '/api/tasks',
  auth,
  asyncRoute(async (req, res) => {
    const documents = await orderedUserTasks(req.user.id);
    res.json(documents.map(mapTask));
  }),
);

app.post(
  '/api/tasks',
  auth,
  asyncRoute(async (req, res) => {
    const now = new Date();
    const task = {
      userId: req.user.id,
      ...taskFields(req.body),
      planOrder: await tasks.countDocuments({ userId: req.user.id }),
      createdAt: now,
      updatedAt: now,
    };
    const result = await tasks.insertOne(task);
    task._id = result.insertedId;
    res.status(201).json(mapTask(task));
  }),
);

app.put(
  '/api/tasks/:id',
  auth,
  asyncRoute(async (req, res) => {
    const id = objectId(req.params.id);
    if (!id) return res.status(404).json({ message: 'Không tìm thấy công việc.' });

    const result = await tasks.findOneAndUpdate(
      { _id: id, userId: req.user.id },
      { $set: { ...taskFields(req.body), updatedAt: new Date() } },
      { returnDocument: 'after' },
    );
    if (!result) {
      return res.status(404).json({ message: 'Không tìm thấy công việc.' });
    }
    res.json(mapTask(result));
  }),
);

app.patch(
  '/api/tasks/:id/status',
  auth,
  asyncRoute(async (req, res) => {
    const id = objectId(req.params.id);
    const status = req.body.status;
    if (!id || !['pending', 'inProgress', 'completed'].includes(status)) {
      return res.status(400).json({ message: 'Trạng thái không hợp lệ.' });
    }
    const result = await tasks.updateOne(
      { _id: id, userId: req.user.id },
      { $set: { status, updatedAt: new Date() } },
    );
    if (!result.matchedCount) {
      return res.status(404).json({ message: 'Không tìm thấy công việc.' });
    }
    res.status(204).end();
  }),
);

async function openAiResponse(input, instructions, format, config) {
  if (!config.apiKey) {
    const error = new Error(
      'Trợ lý AI chưa được cấu hình. Hãy thêm OPENAI_API_KEY vào backend/.env.',
    );
    error.statusCode = 503;
    throw error;
  }
  const response = await fetch(`${config.baseUrl || 'https://api.openai.com'}/v1/responses`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: config.model || 'gpt-5.4-mini',
      instructions,
      input,
      max_output_tokens: format ? 550 : 350,
      store: false,
      ...(format ? { text: { format } } : {}),
    }),
  });
  const data = await response.json();
  if (!response.ok) {
    const upstreamMessage = data.error?.message || 'OpenAI request failed';
    const error = new Error(upstreamMessage);
    error.isOpenAiError = true;
    if (
      data.error?.code === 'insufficient_quota' ||
      /no credits remaining/i.test(upstreamMessage)
    ) {
      error.statusCode = 402;
      error.message =
        'Tài khoản OpenAI API đã hết credits. Hãy bổ sung credits trong phần Billing.';
    } else if (response.status === 401) {
      error.statusCode = 503;
      error.message = 'OPENAI_API_KEY không hợp lệ hoặc đã bị thu hồi.';
    } else if (response.status === 429) {
      error.statusCode = 429;
      error.message = 'OpenAI API đang giới hạn tần suất. Vui lòng thử lại sau.';
    } else {
      error.statusCode = 502;
    }
    throw error;
  }
  return (
    data.output
      ?.flatMap((item) => item.content || [])
      .filter((item) => item.type === 'output_text')
      .map((item) => item.text)
      .join('\n') || ''
  );
}

async function ollamaResponse(input, instructions, format, config) {
  const baseUrl = config.baseUrl || 'http://127.0.0.1:11434';
  let response;
  try {
    response = await fetch(`${baseUrl}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: config.model || 'qwen3:1.7b',
        messages: [
          { role: 'system', content: instructions },
          { role: 'user', content: input },
        ],
        stream: false,
        think: false,
        keep_alive: process.env.OLLAMA_KEEP_ALIVE || '2h',
        ...(format ? { format: format.schema } : {}),
        options: {
          temperature: format ? 0 : 0.55,
          num_predict: format ? 180 : 100,
          num_ctx: format
            ? Number(process.env.OLLAMA_NUM_CTX || 1024)
            : Number(process.env.OLLAMA_CHAT_NUM_CTX || 1024),
          num_thread: Number(
            process.env.OLLAMA_NUM_THREAD ||
              Math.max(2, availableParallelism() - 1),
          ),
        },
      }),
    });
  } catch {
    const error = new Error(
      'Không thể kết nối AI local. Hãy mở Ollama rồi thử lại.',
    );
    error.statusCode = 503;
    error.isAiError = true;
    throw error;
  }

  const data = await response.json();
  if (!response.ok) {
    const error = new Error(data.error || 'Ollama không thể tạo câu trả lời.');
    error.statusCode = 503;
    error.isAiError = true;
    throw error;
  }
  return data.message?.content || '';
}

async function geminiResponse(input, instructions, format, config) {
  if (!config.apiKey) {
    const error = new Error('Gemini API key chưa được cấu hình.');
    error.statusCode = 503;
    throw error;
  }
  const model = config.model || 'gemini-2.5-flash';
  const baseUrl = config.baseUrl || 'https://generativelanguage.googleapis.com';
  const response = await fetch(
    `${baseUrl}/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(config.apiKey)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: instructions }] },
        contents: [{ role: 'user', parts: [{ text: input }] }],
        generationConfig: {
          temperature: format ? 0 : 0.35,
          maxOutputTokens: format ? 550 : 350,
          ...(format
            ? { responseMimeType: 'application/json', responseJsonSchema: format.schema }
            : {}),
        },
      }),
    },
  );
  const data = await response.json();
  if (!response.ok) {
    const error = new Error(data.error?.message || 'Gemini không thể tạo câu trả lời.');
    error.statusCode = response.status === 429 ? 429 : 502;
    error.isAiError = true;
    throw error;
  }
  return data.candidates?.[0]?.content?.parts?.map((part) => part.text || '').join('') || '';
}

async function anthropicResponse(input, instructions, format, config) {
  if (!config.apiKey) {
    const error = new Error('Claude API key chưa được cấu hình.');
    error.statusCode = 503;
    throw error;
  }
  const baseUrl = config.baseUrl || 'https://api.anthropic.com';
  const response = await fetch(`${baseUrl}/v1/messages`, {
    method: 'POST',
    headers: {
      'x-api-key': config.apiKey,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: config.model || 'claude-sonnet-4-5',
      max_tokens: format ? 550 : 350,
      temperature: format ? 0 : 0.35,
      system: `${instructions}${format ? `\nChỉ trả về JSON hợp lệ theo schema: ${JSON.stringify(format.schema)}` : ''}`,
      messages: [{ role: 'user', content: input }],
    }),
  });
  const data = await response.json();
  if (!response.ok) {
    const error = new Error(data.error?.message || 'Claude không thể tạo câu trả lời.');
    error.statusCode = response.status === 429 ? 429 : 502;
    error.isAiError = true;
    throw error;
  }
  return data.content?.filter((item) => item.type === 'text').map((item) => item.text).join('\n') || '';
}

async function aiResponse(input, instructions, format, userId) {
  const startedAt = Date.now();
  const config = await resolveAiConfig(userId);
  let output;
  if (config.provider === 'openai') {
    output = await openAiResponse(input, instructions, format, config);
  } else if (config.provider === 'gemini') {
    output = await geminiResponse(input, instructions, format, config);
  } else if (config.provider === 'anthropic') {
    output = await anthropicResponse(input, instructions, format, config);
  } else {
    output = await ollamaResponse(input, instructions, format, config);
  }
  void aiUsage.insertOne({
    userId,
    provider: config.provider,
    model: config.model,
    latencyMs: Date.now() - startedAt,
    createdAt: new Date(),
  });
  return output;
}

app.post(
  '/api/ai/chat',
  auth,
  asyncRoute(async (req, res) => {
    const question = String(req.body.message || '').trim();
    if (!question) {
      return res.status(400).json({ message: 'Vui lòng nhập câu hỏi.' });
    }
    if (/^(alo|a lô|hello|hi|hey|xin chào|chào)[\s!.?]*$/i.test(question)) {
      return res.json({
        answer:
          'Chào bạn 😄 Mình có thể xem lịch hôm nay, tìm việc cần ưu tiên, kiểm tra task sắp hết hạn hoặc giúp chia nhỏ một công việc.',
      });
    }
    const needsTaskContext =
      /(task|công việc|deadline|hạn chót|hết hạn|lịch|kế hoạch|ưu tiên|tiến độ|việc cần làm|chia nhỏ)/i.test(
        question,
      );
    const currentTasks = needsTaskContext
      ? await tasks
          .find({ userId: req.user.id })
          .sort({ deadline: 1 })
          .limit(50)
          .project({
            title: 1,
            description: 1,
            category: 1,
            priority: 1,
            status: 1,
            estimatedMinutes: 1,
            deadline: 1,
            scheduledStart: 1,
            steps: 1,
          })
          .toArray()
      : [];
    const formatTime = (value) =>
      new Intl.DateTimeFormat('vi-VN', {
        hour: '2-digit',
        minute: '2-digit',
      }).format(new Date(value));
    const formatDateTime = (value) =>
      new Intl.DateTimeFormat('vi-VN', {
        hour: '2-digit',
        minute: '2-digit',
        day: '2-digit',
        month: '2-digit',
      }).format(new Date(value));
    const activeTasks = currentTasks.filter((task) => task.status !== 'completed');
    const asksTodaySchedule =
      /(?:lịch|lịch trình).*(?:hôm nay)|(?:hôm nay).*(?:lịch|việc)/i.test(question);
    if (asksTodaySchedule) {
      const now = new Date();
      const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const end = new Date(start);
      end.setDate(end.getDate() + 1);
      const todayTasks = activeTasks
        .filter((task) => {
          if (!task.scheduledStart) return false;
          const scheduled = new Date(task.scheduledStart);
          return scheduled >= start && scheduled < end;
        })
        .sort((left, right) => new Date(left.scheduledStart) - new Date(right.scheduledStart));
      if (!todayTasks.length) {
        return res.json({
          answer: 'Hôm nay bạn chưa có công việc nào được xếp lịch.',
        });
      }
      return res.json({
        answer: [
          'Lịch hôm nay của bạn:',
          ...todayTasks.map(
            (task, index) =>
              `${index + 1}. ${formatTime(task.scheduledStart)} — ${task.title} (${task.estimatedMinutes} phút)`,
          ),
        ].join('\n'),
      });
    }
    const asksPriority = /(?:việc|task|công việc).*(?:ưu tiên|quan trọng)|(?:ưu tiên).*(?:việc|task|công việc)/i.test(
      question,
    );
    if (asksPriority) {
      const priorityRank = { urgent: 0, high: 1, medium: 2, low: 3 };
      const labels = { urgent: 'Khẩn cấp', high: 'Cao', medium: 'Trung bình', low: 'Thấp' };
      const prioritized = [...activeTasks]
        .sort(
          (left, right) =>
            (priorityRank[left.priority] ?? 9) - (priorityRank[right.priority] ?? 9) ||
            new Date(left.deadline) - new Date(right.deadline),
        )
        .slice(0, 5);
      if (!prioritized.length) {
        return res.json({ answer: 'Bạn chưa có công việc nào cần ưu tiên.' });
      }
      return res.json({
        answer: [
          'Các công việc nên ưu tiên:',
          ...prioritized.map(
            (task, index) =>
              `${index + 1}. ${task.title} — ${labels[task.priority] || task.priority}, hạn ${formatDateTime(task.deadline)}`,
          ),
        ].join('\n'),
      });
    }
    const asksDeadline = /(?:sắp|gần|quá).*(?:hết hạn|deadline|hạn chót)|(?:hết hạn|deadline|hạn chót).*(?:sắp|gần|quá)/i.test(
      question,
    );
    if (asksDeadline) {
      const upcoming = [...activeTasks]
        .sort((left, right) => new Date(left.deadline) - new Date(right.deadline))
        .slice(0, 5);
      if (!upcoming.length) {
        return res.json({ answer: 'Bạn chưa có task nào đang chờ xử lý.' });
      }
      const now = new Date();
      return res.json({
        answer: [
          'Các task gần hạn nhất:',
          ...upcoming.map((task, index) => {
            const overdue = new Date(task.deadline) < now ? ' — đã quá hạn' : '';
            return `${index + 1}. ${task.title} — ${formatDateTime(task.deadline)}${overdue}`;
          }),
        ].join('\n'),
      });
    }
    const asksBreakdown = /(?:chia nhỏ|các bước|bắt đầu).*(?:task|công việc)|(?:task|công việc).*(?:chia nhỏ|các bước|bắt đầu)/i.test(
      question,
    );
    if (asksBreakdown) {
      const normalizedQuestion = question.toLocaleLowerCase('vi-VN');
      const selectedTask = activeTasks.find((task) =>
        normalizedQuestion.includes(String(task.title).toLocaleLowerCase('vi-VN')),
      );
      if (!selectedTask) {
        return res.json({
          answer:
            'Bạn muốn chia nhỏ công việc nào? Hãy nhập tên task, ví dụ: “Chia nhỏ task Viết báo cáo”.',
        });
      }
      const savedSteps = (Array.isArray(selectedTask.steps) ? selectedTask.steps : [])
        .map((step) => String(step.title || '').trim())
        .filter(Boolean);
      const breakdown = savedSteps.length
        ? savedSteps
        : [
            `Xác định kết quả cần đạt của “${selectedTask.title}”.`,
            'Chuẩn bị tài liệu và công cụ cần thiết.',
            'Thực hiện phần chính trong một phiên tập trung.',
            'Kiểm tra kết quả và hoàn thiện phần còn thiếu.',
          ];
      return res.json({
        answer: [
          `Các bước cho “${selectedTask.title}”:`,
          ...breakdown.slice(0, 6).map((step, index) => `${index + 1}. ${step}`),
        ].join('\n'),
      });
    }
    const history = (Array.isArray(req.body.history) ? req.body.history : [])
      .slice(-10)
      .map((item) => ({
        role: item?.role === 'assistant' ? 'assistant' : 'user',
        content: String(item?.content || '').slice(0, 1200),
      }))
      .filter((item) => item.content);
    const conversation = history
      .map(
        (item) =>
          `${item.role === 'assistant' ? 'Trợ lý' : 'Người dùng'}: ${item.content}`,
      )
      .join('\n');
    const taskContext = currentTasks.slice(0, 12).map((task) => ({
          id: task._id.toString(),
          title: task.title,
          description: String(task.description || '').slice(0, 300),
          category: task.category,
          priority: task.priority,
          status: task.status,
          estimatedMinutes: task.estimatedMinutes,
          deadline: task.deadline,
          scheduledStart: task.scheduledStart || null,
          steps: Array.isArray(task.steps)
            ? task.steps.slice(0, 8).map((step) => step.title)
            : [],
        }));
    const input = [
      conversation ? `Lịch sử hội thoại:\n${conversation}` : '',
      `Tin nhắn mới của người dùng: ${question}`,
      taskContext.length
        ? `Dữ liệu công việc chỉ dùng khi cần: ${JSON.stringify(taskContext)}`
        : '',
    ]
      .filter(Boolean)
      .join('\n\n');
    const answer = await aiResponse(
      input,
      [
        'Bạn là trợ lý quản lý công việc Action Planner AI.',
        'LUÔN trả lời hoàn toàn bằng tiếng Việt, trừ khi người dùng yêu cầu ngôn ngữ khác.',
        'Trả lời trực tiếp câu hỏi mới dựa trên lịch sử và dữ liệu công việc được cung cấp.',
        'Không được trả lời chung chung kiểu “để tôi kiểm tra” hoặc hứa sẽ làm sau; phải đưa kết quả ngay trong câu trả lời hiện tại.',
        'Không bịa công việc. Nếu thiếu tên công việc hoặc thông tin cần thiết, hãy hỏi đúng một câu làm rõ.',
        'Khi người dùng yêu cầu chia nhỏ task, đưa ra 3 đến 6 bước hành động ngắn, cụ thể.',
        'Khi người dùng hỏi về lịch, ưu tiên hoặc deadline, dùng đúng dữ liệu công việc và trình bày dạng danh sách dễ đọc.',
        'Ví dụ: “Chia nhỏ task Viết báo cáo” → trả lời các bước cụ thể bằng tiếng Việt.',
        'Ví dụ: “Tôi nên làm gì trước?” → chọn công việc phù hợp từ dữ liệu và giải thích ngắn gọn.',
        'Giữ câu trả lời súc tích, thân thiện và không lặp lại câu trước.',
      ].join(' '),
      null,
      req.user.id,
    );
    res.json({ answer });
  }),
);

app.post(
  '/api/ai/analyze-task',
  auth,
  asyncRoute(async (req, res) => {
    const schema = {
      type: 'json_schema',
      name: 'task_analysis',
      strict: true,
      schema: {
        type: 'object',
        additionalProperties: false,
        properties: {
          priority: {
            type: 'string',
            enum: ['low', 'medium', 'high', 'urgent'],
          },
          estimatedMinutes: { type: 'integer', minimum: 5, maximum: 1440 },
          steps: {
            type: 'array',
            minItems: 1,
            maxItems: 3,
            items: { type: 'string' },
          },
          suggestion: { type: 'string' },
        },
        required: ['priority', 'estimatedMinutes', 'steps', 'suggestion'],
      },
    };
    const title = String(req.body.title || '').trim();
    const description = String(req.body.description || '');
    const output = await aiResponse(
      JSON.stringify({
        title,
        description,
      }),
      'Phân tích nhanh công việc. Note của người dùng là yêu cầu bắt buộc. Nếu note nói làm trước, đặt priority high hoặc urgent và nhắc trong suggestion. Trả đúng 3 bước hành động cực ngắn bằng tiếng Việt; không giải thích ngoài JSON.',
      schema,
      req.user.id,
    );
    const analysis = parseAiJson(output);
    const normalizedDescription = normalizedVietnamese(description);
    const explicitMinutes = normalizedDescription.match(/(\d+)\s*(?:phut|p)\b/);
    const explicitHours = normalizedDescription.match(
      /(\d+(?:[.,]\d+)?)\s*(?:gio|tieng)\b/,
    );
    if (explicitMinutes) {
      analysis.estimatedMinutes = Number(explicitMinutes[1]);
    } else if (explicitHours) {
      analysis.estimatedMinutes = Math.round(
        Number(explicitHours[1].replace(',', '.')) * 60,
      );
    }
    if (/(?:gap|khan|hom nay|cang som)/.test(normalizedDescription)) {
      analysis.priority = 'urgent';
    } else if (hasExplicitOrderNote({ description })) {
      analysis.priority = 'high';
      analysis.suggestion = `Ưu tiên “${title}” làm trước theo ghi chú của bạn.`;
    }
    res.json(analysis);
  }),
);

app.post(
  '/api/plans/replan',
  auth,
  asyncRoute(async (req, res) => {
    const documents = await tasks
      .find({ userId: req.user.id, status: { $ne: 'completed' } })
      .toArray();
    if (documents.length === 0) {
      return res.json({ summary: 'Không có công việc cần sắp xếp.', tasks: [] });
    }

    const rawFeedback = String(req.body.feedback || '');
    const feedback = normalizedVietnamese(
      rawFeedback.replace(/REJECTED_ORDER:[a-f\d,]+/i, ''),
    );
    const priorityOrder = { low: 1, medium: 2, high: 3, urgent: 4 };
    const wantsShortFirst = /(?:ngan|nhanh).{0,20}(?:truoc|dau tien)/.test(
      feedback,
    );
    const wantsLongFirst = /(?:dai|lau).{0,20}(?:truoc|dau tien)/.test(
      feedback,
    );
    const wantsDeadlineFirst =
      /(?:deadline|han).{0,20}(?:gan|truoc|som)/.test(feedback);
    const mentionsFirst = /(?:truoc|dau tien|uu tien)/.test(feedback);

    const ordered = [...documents].sort((left, right) => {
      if (mentionsFirst) {
        const mentioned = Number(taskMentionedInFeedback(right, feedback)) -
          Number(taskMentionedInFeedback(left, feedback));
        if (mentioned) return mentioned;
      }
      const notePriority = Number(hasExplicitOrderNote(right)) -
        Number(hasExplicitOrderNote(left));
      if (notePriority) return notePriority;
      if (wantsShortFirst && left.estimatedMinutes !== right.estimatedMinutes) {
        return left.estimatedMinutes - right.estimatedMinutes;
      }
      if (wantsLongFirst && left.estimatedMinutes !== right.estimatedMinutes) {
        return right.estimatedMinutes - left.estimatedMinutes;
      }
      if (wantsDeadlineFirst) {
        const deadline = new Date(left.deadline) - new Date(right.deadline);
        if (deadline) return deadline;
      }
      const priority =
        (priorityOrder[right.priority] || 1) -
        (priorityOrder[left.priority] || 1);
      return priority || new Date(left.deadline) - new Date(right.deadline);
    });

    const rejectedMatch = rawFeedback.match(/REJECTED_ORDER:([a-f\d,]+)/i);
    if (rejectedMatch && ordered.length > 1) {
      const rejectedIds = rejectedMatch[1].split(',').filter(Boolean);
      const proposedIds = ordered.map((task) => task._id.toString());
      const isSameOrder =
        rejectedIds.length === proposedIds.length &&
        rejectedIds.every((id, index) => id === proposedIds[index]);
      if (isSameOrder) {
        const movableIndex = ordered.findIndex(
          (task) =>
            !hasExplicitOrderNote(task) &&
            !(mentionsFirst && taskMentionedInFeedback(task, feedback)),
        );
        if (movableIndex >= 0 && movableIndex < ordered.length - 1) {
          const [task] = ordered.splice(movableIndex, 1);
          ordered.splice(movableIndex + 1, 0, task);
        }
      }
    }

    for (const task of ordered) {
      if (mentionsFirst && taskMentionedInFeedback(task, feedback)) {
        task.aiSuggestion = 'Được xếp trước theo yêu cầu mới của bạn.';
      } else if (hasExplicitOrderNote(task)) {
        task.aiSuggestion = 'Được xếp trước theo ghi chú của bạn.';
      } else if (wantsShortFirst) {
        task.aiSuggestion = `Thời lượng ${task.estimatedMinutes} phút.`;
      }
    }

    const summary = feedback
      ? 'Đã sắp xếp lại ngay theo yêu cầu mới và ghi chú của bạn.'
      : 'Đã ưu tiên ghi chú của bạn, sau đó xét mức ưu tiên và deadline.';
    res.set('X-Plan-Engine', 'fast-note-aware');
    res.json({ summary, tasks: ordered.map(mapTask) });
  }),
);

app.post(
  '/api/plans/replan/accept',
  auth,
  asyncRoute(async (req, res) => {
    const proposedTasks = Array.isArray(req.body.tasks) ? req.body.tasks : [];
    let scheduleCursor = new Date();
    scheduleCursor.setSeconds(0, 0);
    const operations = proposedTasks
      .map((task, index) => {
        const id = objectId(task.id);
        if (!id) return null;
        const scheduledStart = new Date(scheduleCursor);
        const minutes = Math.max(1, Number(task.estimatedMinutes) || 30);
        scheduleCursor = new Date(
          scheduleCursor.getTime() + (minutes + 10) * 60 * 1000,
        );
        return {
          updateOne: {
            filter: { _id: id, userId: req.user.id },
            update: {
              $set: {
                planOrder: index,
                scheduledStart,
                aiSuggestion: task.aiSuggestion
                  ? String(task.aiSuggestion)
                  : null,
                updatedAt: new Date(),
              },
            },
          },
        };
      })
      .filter(Boolean);
    if (operations.length > 0) await tasks.bulkWrite(operations);

    const accepted = await orderedUserTasks(req.user.id);
    res.json(accepted.map(mapTask));
  }),
);

app.get(
  '/api/settings/ai',
  auth,
  asyncRoute(async (req, res) => {
    const personal = await userSettings.findOne({ userId: req.user.id });
    if (personal) {
      return res.json(
        publicAiConfig(
          { ...personal, apiKey: decryptSecret(personal.encryptedApiKey), source: 'personal' },
          Boolean(personal.customAiEnabled),
        ),
      );
    }
    const resolved = await resolveAiConfig(req.user.id);
    res.json(publicAiConfig(resolved, false));
  }),
);

app.put(
  '/api/settings/ai',
  auth,
  asyncRoute(async (req, res) => {
    const fields = validateAiSettings(req.body);
    // Endpoint tùy chỉnh chỉ thuộc quyền admin để tránh user lợi dụng backend
    // truy cập dịch vụ nội bộ (SSRF). User vẫn chọn provider/model/key riêng.
    fields.baseUrl = '';
    const current = await userSettings.findOne({ userId: req.user.id });
    const update = {
      ...fields,
      customAiEnabled: Boolean(req.body.customAiEnabled),
      updatedAt: new Date(),
    };
    if (String(req.body.apiKey || '').trim()) {
      update.encryptedApiKey = encryptSecret(String(req.body.apiKey).trim());
    } else if (req.body.clearApiKey === true) {
      update.encryptedApiKey = null;
    } else if (current?.encryptedApiKey) {
      update.encryptedApiKey = current.encryptedApiKey;
    }
    await userSettings.updateOne(
      { userId: req.user.id },
      { $set: update, $setOnInsert: { userId: req.user.id, createdAt: new Date() } },
      { upsert: true },
    );
    res.json(publicAiConfig({ ...update, source: 'personal' }, update.customAiEnabled));
  }),
);

app.post(
  '/api/settings/ai/test',
  auth,
  asyncRoute(async (req, res) => {
    const answer = await aiResponse(
      'Hãy trả lời đúng một từ: OK',
      'Bạn đang kiểm tra kết nối. Trả lời cực ngắn.',
      null,
      req.user.id,
    );
    res.json({ ok: Boolean(answer.trim()), answer: answer.trim() });
  }),
);

app.post(
  '/api/feedback',
  auth,
  asyncRoute(async (req, res) => {
    const type = ['suggestion', 'complaint', 'rating'].includes(req.body.type)
      ? req.body.type
      : 'suggestion';
    const message = String(req.body.message || '').trim();
    const rating = Number(req.body.rating || 0);
    if (!message && !(rating >= 1 && rating <= 5)) {
      return res.status(400).json({ message: 'Vui lòng nhập nội dung hoặc đánh giá.' });
    }
    const item = {
      userId: req.user.id,
      type,
      message,
      rating: rating >= 1 && rating <= 5 ? rating : null,
      status: 'open',
      createdAt: new Date(),
      updatedAt: new Date(),
    };
    const result = await feedback.insertOne(item);
    res.status(201).json({ id: result.insertedId.toString(), ...item });
  }),
);

app.get(
  '/api/feedback',
  auth,
  asyncRoute(async (req, res) => {
    const items = await feedback
      .find({ userId: req.user.id })
      .sort({ createdAt: -1 })
      .limit(100)
      .toArray();
    res.json(items.map((item) => ({
      id: item._id.toString(),
      type: item.type,
      message: item.message,
      rating: item.rating,
      status: item.status,
      adminReply: item.adminReply || '',
      repliedAt: item.repliedAt || null,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
    })));
  }),
);

app.get(
  '/api/admin/dashboard',
  auth,
  adminOnly,
  asyncRoute(async (_req, res) => {
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const [totalUsers, activeUsers, totalTasks, openComplaints, ratingData, usageData] =
      await Promise.all([
        users.countDocuments(),
        users.countDocuments({ lastActiveAt: { $gte: sevenDaysAgo } }),
        tasks.countDocuments(),
        feedback.countDocuments({ type: 'complaint', status: 'open' }),
        feedback.aggregate([
          { $match: { rating: { $gte: 1, $lte: 5 } } },
          { $group: { _id: null, average: { $avg: '$rating' }, count: { $sum: 1 } } },
        ]).next(),
        aiUsage.aggregate([
          { $match: { createdAt: { $gte: sevenDaysAgo } } },
          { $group: { _id: null, requests: { $sum: 1 }, averageLatencyMs: { $avg: '$latencyMs' } } },
        ]).next(),
      ]);
    res.json({
      totalUsers,
      activeUsers7d: activeUsers,
      totalTasks,
      openComplaints,
      averageRating: ratingData?.average || 0,
      ratingCount: ratingData?.count || 0,
      aiRequests7d: usageData?.requests || 0,
      averageAiLatencyMs: Math.round(usageData?.averageLatencyMs || 0),
    });
  }),
);

app.get(
  '/api/admin/users',
  auth,
  adminOnly,
  asyncRoute(async (req, res) => {
    const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 50));
    const items = await users
      .find({}, { projection: { passwordHash: 0 } })
      .sort({ createdAt: -1 })
      .limit(limit)
      .toArray();
    res.json(items.map(mapUser));
  }),
);

app.get(
  '/api/admin/feedback',
  auth,
  adminOnly,
  asyncRoute(async (req, res) => {
    const status = String(req.query.status || '');
    const query = status ? { status } : {};
    const items = await feedback.find(query).sort({ createdAt: -1 }).limit(100).toArray();
    const userIds = [...new Set(items.map((item) => item.userId.toString()))].map(
      (id) => new ObjectId(id),
    );
    const owners = await users.find({ _id: { $in: userIds } }).toArray();
    const ownerById = new Map(owners.map((user) => [user._id.toString(), mapUser(user)]));
    res.json(items.map((item) => ({
      id: item._id.toString(),
      type: item.type,
      message: item.message,
      rating: item.rating,
      status: item.status,
      adminReply: item.adminReply || '',
      repliedAt: item.repliedAt || null,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      user: ownerById.get(item.userId.toString()),
    })));
  }),
);

app.patch(
  '/api/admin/feedback/:id',
  auth,
  adminOnly,
  asyncRoute(async (req, res) => {
    const id = objectId(req.params.id);
    const status = String(req.body.status || '');
    const adminReply = String(req.body.adminReply || '').trim();
    if (!id || !['open', 'inProgress', 'resolved'].includes(status)) {
      return res.status(400).json({ message: 'Trạng thái không hợp lệ.' });
    }
    if (adminReply.length > 2000) {
      return res.status(400).json({ message: 'Câu trả lời tối đa 2000 ký tự.' });
    }
    const now = new Date();
    const update = { status, updatedAt: now };
    if (adminReply) {
      update.adminReply = adminReply;
      update.repliedAt = now;
      update.repliedBy = req.user.id;
    }
    const result = await feedback.updateOne({ _id: id }, { $set: update });
    if (!result.matchedCount) {
      return res.status(404).json({ message: 'Không tìm thấy phản hồi.' });
    }
    res.status(204).end();
  }),
);

app.get(
  '/api/admin/settings/ai',
  auth,
  adminOnly,
  asyncRoute(async (_req, res) => {
    const saved = await appSettings.findOne({ _id: 'default-ai' });
    const config = saved || envAiConfig();
    res.json(publicAiConfig({ ...config, source: saved ? 'admin' : 'environment' }));
  }),
);

app.put(
  '/api/admin/settings/ai',
  auth,
  adminOnly,
  asyncRoute(async (req, res) => {
    const fields = validateAiSettings(req.body);
    const current = await appSettings.findOne({ _id: 'default-ai' });
    const update = { ...fields, updatedAt: new Date(), updatedBy: req.user.id };
    if (String(req.body.apiKey || '').trim()) {
      update.encryptedApiKey = encryptSecret(String(req.body.apiKey).trim());
    } else if (req.body.clearApiKey === true) {
      update.encryptedApiKey = null;
    } else if (current?.encryptedApiKey) {
      update.encryptedApiKey = current.encryptedApiKey;
    }
    await appSettings.updateOne(
      { _id: 'default-ai' },
      { $set: update, $setOnInsert: { createdAt: new Date() } },
      { upsert: true },
    );
    res.json(publicAiConfig({ ...update, source: 'admin' }));
  }),
);

app.use((error, _req, res, _next) => {
  console.error(error);
  const duplicate = error?.code === 11000;
  res.status(duplicate ? 409 : error.statusCode || 500).json({
    message: duplicate ? 'Email đã được sử dụng.' : error.message || 'Máy chủ gặp lỗi.',
    detail: process.env.NODE_ENV === 'production' ? undefined : error.message,
  });
});

async function start() {
  if (!process.env.JWT_SECRET) {
    throw new Error('JWT_SECRET chưa được cấu hình trong backend/.env.');
  }
  await mongoClient.connect();
  const adminEmail = String(process.env.ADMIN_EMAIL || '').trim().toLowerCase();
  if (adminEmail) {
    const existingAdmin = await users.findOne({ email: adminEmail });
    if (existingAdmin) {
      const adminUpdates = { role: 'admin', updatedAt: new Date() };
      if (
        process.env.ADMIN_PASSWORD &&
        !(await bcrypt.compare(process.env.ADMIN_PASSWORD, existingAdmin.passwordHash))
      ) {
        adminUpdates.passwordHash = await bcrypt.hash(
          process.env.ADMIN_PASSWORD,
          12,
        );
      }
      await users.updateOne(
        { _id: existingAdmin._id },
        { $set: adminUpdates },
      );
    } else if (process.env.ADMIN_PASSWORD) {
      await users.insertOne({
        fullName: process.env.ADMIN_NAME || 'Quản trị viên',
        email: adminEmail,
        passwordHash: await bcrypt.hash(process.env.ADMIN_PASSWORD, 12),
        role: 'admin',
        createdAt: new Date(),
        updatedAt: new Date(),
      });
    }
  }
  await Promise.all([
    users.createIndex({ email: 1 }, { unique: true }),
    tasks.createIndex({ userId: 1, status: 1, deadline: 1 }),
    userSettings.createIndex({ userId: 1 }, { unique: true }),
    feedback.createIndex({ status: 1, createdAt: -1 }),
    feedback.createIndex({ userId: 1, createdAt: -1 }),
    aiUsage.createIndex({ createdAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 90 }),
  ]);

  const port = Number(process.env.PORT || 3000);
  app.listen(port, () => {
    console.log(`Action Planner API: http://localhost:${port}`);
    console.log(`MongoDB database: ${database.databaseName}`);
  });
}

start().catch((error) => {
  console.error('Không thể khởi động backend:', error);
  process.exitCode = 1;
});
