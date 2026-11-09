#include "mic.h"

#include <QtMultimedia/QAudioDevice>
#include <QtMultimedia/QAudioSource>
#include <QtMultimedia/QMediaDevices>
#include <cmath>
#include <cstring>

extern "C"
{
  float arara_pitch(const float* ptr, size_t len, unsigned int rate);
  void arara_chroma(const float* ptr, size_t len, unsigned int rate, float* out);
}

namespace {
// Amostras analisadas de cada vez (~0,19 s a 44,1 kHz): pega até o Mi grave.
constexpr int kWindow = 8192;
}

Mic::Mic(QObject* parent)
  : QObject(parent)
{
  m_timer.setInterval(80);
  connect(&m_timer, &QTimer::timeout, this, &Mic::analyse);
  for (int i = 0; i < 12; ++i)
    m_chroma.append(0.0);
}

Mic::~Mic()
{
  setActive(false);
}

void
Mic::setError(const QString& e)
{
  if (e == m_error)
    return;
  m_error = e;
  emit errorChanged();
}

void
Mic::setActive(bool on)
{
  if (on == active())
    return;
  if (!on) {
    m_timer.stop();
    m_source->stop();
    delete m_source;
    m_source = nullptr;
    m_io = nullptr;
    m_buffer.clear();
    m_frequency = 0;
    m_level = 0;
    emit updated();
    emit activeChanged();
    return;
  }
  const QAudioDevice dev = QMediaDevices::defaultAudioInput();
  if (dev.isNull()) {
    setError(QStringLiteral("Nenhum microfone encontrado."));
    return;
  }
  QAudioFormat f;
  f.setSampleRate(44100);
  f.setChannelCount(1);
  f.setSampleFormat(QAudioFormat::Float);
  if (!dev.isFormatSupported(f))
    f = dev.preferredFormat();
  m_format = f;
  m_source = new QAudioSource(dev, f, this);
  m_io = m_source->start();
  if (!m_io) {
    delete m_source;
    m_source = nullptr;
    setError(QStringLiteral("Não deu para abrir o microfone."));
    return;
  }
  connect(m_io, &QIODevice::readyRead, this, &Mic::readAudio);
  setError(QString());
  m_timer.start();
  emit activeChanged();
}

void
Mic::readAudio()
{
  if (!m_io)
    return;
  const QByteArray data = m_io->readAll();
  const int ch = qMax(1, m_format.channelCount());
  const int bytes = m_format.bytesPerSample();
  if (bytes <= 0)
    return;
  const int frames = data.size() / (bytes * ch);
  const char* p = data.constData();
  for (int i = 0; i < frames; ++i) {
    const char* s = p + i * bytes * ch; // só o primeiro canal
    float v = 0;
    switch (m_format.sampleFormat()) {
      case QAudioFormat::Float:
        std::memcpy(&v, s, 4);
        break;
      case QAudioFormat::Int16: {
        qint16 x;
        std::memcpy(&x, s, 2);
        v = x / 32768.0f;
        break;
      }
      case QAudioFormat::Int32: {
        qint32 x;
        std::memcpy(&x, s, 4);
        v = x / 2147483648.0f;
        break;
      }
      case QAudioFormat::UInt8:
        v = (static_cast<unsigned char>(*s) - 128) / 128.0f;
        break;
      default:
        break;
    }
    m_buffer.append(v);
  }
  if (m_buffer.size() > kWindow)
    m_buffer.remove(0, m_buffer.size() - kWindow);
}

void
Mic::analyse()
{
  if (m_buffer.size() < kWindow / 2)
    return;
  const unsigned rate = static_cast<unsigned>(m_format.sampleRate());
  double sum = 0;
  for (float v : m_buffer)
    sum += double(v) * v;
  m_level = std::sqrt(sum / m_buffer.size());
  // Afinador: só a parte mais recente (resposta rápida).
  const int n = qMin<int>(m_buffer.size(), 4096);
  m_frequency = arara_pitch(m_buffer.constData() + m_buffer.size() - n, n, rate);
  float c[12] = {};
  arara_chroma(m_buffer.constData(), m_buffer.size(), rate, c);
  for (int i = 0; i < 12; ++i)
    m_chroma[i] = double(c[i]);
  emit updated();
}
