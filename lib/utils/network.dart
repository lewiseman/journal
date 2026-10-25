import 'package:connectivity_plus/connectivity_plus.dart';


// final Provider<NetworkService> networkServiceProvider =
//     Provider<NetworkService>((ref) {
//       return NetworkService();
//     });

enum NetworkType { none, mobile, wifiOrEthernet }

class NetworkService {
  final Connectivity _connectivity;

  NetworkService([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  Future<bool> isOnline() async {
    // final type = await getCurrentNetworkType();
    // return type != NetworkType.none;
    return true;
  }
}
