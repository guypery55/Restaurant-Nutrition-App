import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/restaurant.dart';
import '../../services/restaurant_service.dart';

/// Restaurant search & resolution (Session 2).
///
/// The user types a name (Hebrew or English); we query Places Autocomplete via
/// the `resolve-restaurant` function and show candidate branches with their
/// addresses. Tapping one resolves it to a canonical `restaurants` row and pops
/// that [Restaurant] back to the caller.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<RestaurantCandidate> _candidates = const [];
  bool _searching = false;
  bool _selecting = false;
  String? _error;

  // Guards against out-of-order autocomplete responses (a slow earlier request
  // landing after a faster later one).
  int _queryToken = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(value.trim());
    });
  }

  Future<void> _runSearch(String input) async {
    if (input.isEmpty) {
      setState(() {
        _candidates = const [];
        _error = null;
        _searching = false;
      });
      return;
    }
    final token = ++_queryToken;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await RestaurantService.autocomplete(input);
      if (token != _queryToken || !mounted) return; // stale response
      setState(() {
        _candidates = results;
        _searching = false;
      });
    } catch (e) {
      if (token != _queryToken || !mounted) return;
      setState(() {
        _error = 'החיפוש נכשל. נסו שוב.';
        _searching = false;
      });
    }
  }

  Future<void> _select(RestaurantCandidate candidate) async {
    setState(() => _selecting = true);
    try {
      final restaurant = await RestaurantService.select(candidate.placeId);
      if (!mounted) return;
      Navigator.of(context).pop(restaurant);
    } catch (e) {
      if (!mounted) return;
      setState(() => _selecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('בחירת המסעדה נכשלה. נסו שוב.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('חיפוש מסעדה')),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  decoration: InputDecoration(
                    hintText: 'הקלידו שם מסעדה…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : (_controller.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _controller.clear();
                                  _runSearch('');
                                  setState(() {});
                                },
                              )
                            : null),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(child: _buildResults(context)),
            ],
          ),
          if (_selecting)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_candidates.isEmpty) {
      final hasQuery = _controller.text.trim().isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            hasQuery && !_searching
                ? 'לא נמצאו מסעדות מתאימות.'
                : 'הקלידו שם של מסעדה כדי לחפש.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _candidates.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = _candidates[i];
        return ListTile(
          leading: const Icon(Icons.restaurant_outlined),
          title: Text(c.name),
          subtitle: c.address.isNotEmpty ? Text(c.address) : null,
          onTap: _selecting ? null : () => _select(c),
        );
      },
    );
  }
}
