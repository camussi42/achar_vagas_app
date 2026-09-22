/// Provider de tiles usado nos testes de widget.
///
/// O `flutter_test` bloqueia HTTP (toda requisicao devolve 400), entao o mapa
/// nao pode buscar tiles reais: aqui ele recebe um PNG transparente — o mesmo
/// truque usado nos testes do proprio flutter_map (`TileProvider.transparentImage`).
library;

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

class TilesFalsos extends TileProvider {
  @override
  ImageProvider<Object> getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) =>
      MemoryImage(TileProvider.transparentImage);
}
