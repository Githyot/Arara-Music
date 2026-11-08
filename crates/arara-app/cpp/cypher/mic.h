// Microfone para o afinador e para o "Tocar junto": lê o som da entrada
// padrão e, algumas vezes por segundo, calcula (no núcleo em Rust) a nota que
// está soando e a força de cada uma das 12 notas.
#pragma once

#include <QtCore/QObject>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>
#include <QtCore/QVector>
#include <QtMultimedia/QAudioFormat>

class QAudioSource;
class QIODevice;

class Mic : public QObject
{
  Q_OBJECT
  Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
  Q_PROPERTY(double frequency READ frequency NOTIFY updated)
  Q_PROPERTY(double level READ level NOTIFY updated)
  Q_PROPERTY(QVariantList chroma READ chroma NOTIFY updated)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
  explicit Mic(QObject* parent = nullptr);
  ~Mic() override;

  bool active() const { return m_source != nullptr; }
  void setActive(bool on);
  double frequency() const { return m_frequency; }
  double level() const { return m_level; }
  QVariantList chroma() const { return m_chroma; }
  QString error() const { return m_error; }

signals:
  void activeChanged();
  void updated();
  void errorChanged();

private:
  void readAudio();
  void analyse();
  void setError(const QString& e);

  QAudioSource* m_source = nullptr;
  QIODevice* m_io = nullptr;
  QAudioFormat m_format;
  QVector<float> m_buffer; // últimas amostras (mono)
  QTimer m_timer;
  double m_frequency = 0;
  double m_level = 0;
  QVariantList m_chroma;
  QString m_error;
};
