import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkType { none, mobile, wifiOrEthernet }

abstract interface class SyncNetwork {
  Future<bool> isOnline();
}

class NetworkService implements SyncNetwork {
  final Connectivity _connectivity;

  NetworkService([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  Stream<NetworkType> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged.map(_mapResults);
  }

  Future<NetworkType> getCurrentNetworkType() async {
    final results = await _connectivity.checkConnectivity();
    return _mapResults(results);
  }

  @override
  Future<bool> isOnline() async {
    final type = await getCurrentNetworkType();
    return type != NetworkType.none;
  }

  Future<bool> isUnmeteredConnection() async {
    final type = await getCurrentNetworkType();
    return type == NetworkType.wifiOrEthernet;
  }

  NetworkType _mapResults(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return NetworkType.wifiOrEthernet;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return NetworkType.mobile;
    }
    return results.any((result) => result != ConnectivityResult.none)
        ? NetworkType.mobile
        : NetworkType.none;
  }
}
