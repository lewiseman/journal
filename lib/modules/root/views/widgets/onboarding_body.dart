import 'dart:async';

import 'package:journal/common.dart';
import 'package:journal/modules/root/views/widgets/onboarding_content.dart';

enum _Stage { touring, closing, naming, saving, opening }

class OnboardingBody extends StatefulWidget {
  const new({super.key});

  @override
  State<OnboardingBody> createState() => _OnboardingBodyState();
}

class _OnboardingBodyState extends State<OnboardingBody>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _turn = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
    duration: const Duration(milliseconds: 850),
  );
  late final _close = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
    duration: const Duration(milliseconds: 1100),
  );
  final _name = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  _Stage _stage = _Stage.touring;
  int _page = 0;
  int _direction = 1;
  bool _turning = false;
  bool _dragging = false;
  bool _reduced = false;
  bool _active = true;
  bool _visible = true;
  bool _paused = false;
  bool _beginPending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _name.addListener(_nameChanged);
  }

  void _nameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    _visible =
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        TickerMode.valuesOf(context).enabled;
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_stage != _Stage.touring ||
        _turning ||
        _dragging ||
        _reduced ||
        !_active ||
        !_visible ||
        _paused ||
        _page == 5) {
      return;
    }
    _timer = Timer(const Duration(seconds: 5), () => _flip(1));
  }

  Future<void> _flip(int direction) async {
    if (_turning ||
        _stage != _Stage.touring ||
        _page + direction < 0 ||
        _page + direction > 5) {
      return;
    }
    _timer?.cancel();
    setState(() {
      _direction = direction;
      _turning = true;
    });
    await _finishTurn(true);
  }

  Future<void> _finishTurn(bool commit) async {
    try {
      if (_reduced) {
        _turn.value = commit ? 1 : 0;
      } else {
        await _turn
            .animateTo(commit ? 1 : 0, curve: Curves.easeOutCubic)
            .orCancel;
      }
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    setState(() {
      if (commit) _page += _direction;
      _turning = false;
      _turn.value = 0;
    });
    if (_beginPending) {
      _beginPending = false;
      await _begin();
    } else {
      _schedule();
    }
  }

  Future<void> _begin() async {
    if (_stage != _Stage.touring) return;
    _timer?.cancel();
    if (_turning) {
      _beginPending = true;
      if (_dragging) {
        _dragging = false;
        unawaited(_finishTurn(true));
      }
      return;
    }
    setState(() => _stage = _Stage.closing);
    try {
      if (_reduced) {
        _close.value = 1;
      } else {
        await _close.forward().orCancel;
      }
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    setState(() => _stage = _Stage.naming);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _stage == _Stage.naming) _focus.requestFocus();
    });
  }

  Future<void> _save() async {
    final value = _name.text.trim();
    if (_stage != _Stage.naming || value.isEmpty) return;
    setState(() {
      _stage = _Stage.saving;
      _error = null;
    });
    try {
      await CacheStorage.instance.set(userNameKey, value);
      if (!mounted) return;
      _focus.unfocus();
      unawaited(
        Navigator.of(context).pushAndRemoveUntil<void>(
          MaterialPageRoute(builder: (_) => const RootLayout()),
          (_) => false,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _stage = _Stage.naming;
          _error = 'Couldn’t save your name. Please try again.';
        });
      }
    }
  }

  Future<void> _back() async {
    if (_stage != _Stage.naming) return;
    if (_focus.hasFocus || MediaQuery.viewInsetsOf(context).bottom > 0) {
      _focus.unfocus();
      return;
    }
    setState(() {
      _stage = _Stage.opening;
      _paused = true;
      _error = null;
    });
    try {
      if (_reduced) {
        _close.value = 0;
      } else {
        await _close.reverse().orCancel;
      }
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    setState(() => _stage = _Stage.touring);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _turn.dispose();
    _close.dispose();
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startDrag() {
    _timer?.cancel();
    _dragging = true;
  }

  void _updateDrag(double delta, double width) {
    if (!_dragging || _stage != _Stage.touring) return;
    if (!_turning) {
      final direction = delta < 0 ? 1 : -1;
      if (_page + direction < 0 || _page + direction > 5) return;
      setState(() {
        _direction = direction;
        _turning = true;
      });
    }
    _turn.value = (_turn.value - delta * _direction / (width * .65)).clamp(
      0.0,
      1.0,
    );
  }

  void _endDrag(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    if (_turning) {
      unawaited(_finishTurn(_turn.value > .25 || velocity * _direction < -350));
    } else {
      _schedule();
    }
  }

  void _cancelDrag() {
    if (!_dragging) return;
    _dragging = false;
    if (_turning) {
      unawaited(_finishTurn(false));
    } else {
      _schedule();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _stage == _Stage.touring,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_back());
    },
    child: OnboardingContent(
      page: _page,
      direction: _direction,
      turn: _turn,
      close: _close,
      turning: _turning,
      touring: _stage == _Stage.touring,
      naming: _stage == _Stage.naming || _stage == _Stage.saving,
      saving: _stage == _Stage.saving,
      nameController: _name,
      nameFocus: _focus,
      error: _error,
      onBegin: _begin,
      onSave: _save,
      onFlip: _flip,
      onDragStart: _startDrag,
      onDragUpdate: _updateDrag,
      onDragEnd: _endDrag,
      onDragCancel: _cancelDrag,
    ),
  );
}
