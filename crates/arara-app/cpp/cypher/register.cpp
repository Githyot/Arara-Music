// Arara Cypher (aba Estudos): registra o microfone do afinador e do "Tocar
// junto" como `import AraraCypher.Audio` (Mic). Chamado pelo main.rs antes
// de carregar o QML.
#include <QtQml/qqml.h>

#include "mic.h"

extern "C" void
arara_cypher_register_types()
{
  qmlRegisterType<Mic>("AraraCypher.Audio", 1, 0, "Mic");
}
