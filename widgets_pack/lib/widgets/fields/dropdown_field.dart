import 'dart:async';

import 'package:extensions_pack/extensions_pack.dart';
import 'package:flutter/material.dart';
import 'package:widgets_pack/widgets_pack.dart';

class AppDropDownFormField<T extends Object> extends StatefulWidget {
  final AppItemsFetcher<T> fetcher;
  final AppItemsHandler<T> handler;
  final String? labelText;
  final String? hintText;
  final AppItemsValidator<T>? validator;
  final InputBorder? border;
  final EdgeInsets? inputContentPadding;
  final EdgeInsets? tilesContentPadding;
  final bool showTrailing;
  final AppTextFormFieldErrorType errorType;
  final Widget Function(T item, bool selected, VoidCallback onTap)? tileBuilder;
  final bool enabled;

  const AppDropDownFormField({
    required this.fetcher,
    required this.handler,
    this.labelText,
    this.hintText,
    this.validator,
    this.border,
    this.inputContentPadding,
    this.tilesContentPadding,
    this.showTrailing = true,
    this.errorType = AppTextFormFieldErrorType.string,
    this.tileBuilder,
    this.enabled = true,
    super.key,
  });

  @override
  State<AppDropDownFormField<T>> createState() => _AppDropDownFormFieldState<T>();
}

class _AppDropDownFormFieldState<T extends Object> extends State<AppDropDownFormField<T>> {
  final _widgetKey = GlobalKey();

  RenderBox? get _renderBox {
    return _widgetKey.currentContext?.findRenderObject() as RenderBox?;
  }

  Size? get _widgetSize {
    return _renderBox?.size;
  }

  final _layerLink = LayerLink();
  final _textController = TextEditingController();
  final _textFocusNode = FocusNode();
  final _searchDebouncer = Debouncer(
    duration: const Duration(milliseconds: 350),
  );

  final _itemNotifier = ValueNotifier<List<T>>([]);
  final _filteredItemsNotifier = ValueNotifier<List<T>>([]);

  late final _selectedItemNotifier = ValueNotifier<List<T>>(
    switch (widget.handler) {
      (AppSingleItemHandler<T>()) => [(widget.handler as AppSingleItemHandler<T>).initialValue].whereNotNull().toList(),
      (AppMultipleItemsHandler<T>()) => (widget.handler as AppMultipleItemsHandler<T>).initialValue,
    },
  );

  late final _hasItemsNotifier = ValueNotifier<bool>(
    _selectedItemNotifier.value.isNotEmpty,
  );

  bool _loadedAll = false;
  bool _loading = false;
  String? _lastSearch;

  OverlayEntry? _overlayEntry;

  Future<void> _search(String search) async {
    _lastSearch = search;

    await switch (widget.fetcher) {
      (AppRemoteListItemsFetcher<T>()) => _remoteListFetcher(search),
      (AppLocalItemsFetcher<T>()) => _localListFetcher(search),
      (AppRemoteSearchListItemsFetcher<T>()) => _remoteSearchFetcher(search),
      (_) => throw UnimplementedError('Fetcher not implemented'),
    };

    _filteredItemsNotifier.value = _itemNotifier.value.where((item) {
      return widget.handler.asString(item).toLowerCase().contains(search.toLowerCase());
    }).toList();
  }

  Future<void> _localListFetcher(String search) async {
    if (_loadedAll) {
      return;
    }

    final fetcher = widget.fetcher as AppLocalItemsFetcher<T>;
    final items = fetcher.items;

    setState(() => _loadedAll = true);

    _itemNotifier.value = items;
  }

  Future<void> _remoteListFetcher(String search) async {
    if (_loadedAll || _loading) {
      return;
    }

    _setLoading(true);

    final fetcher = widget.fetcher as AppRemoteListItemsFetcher<T>;
    final items = await fetcher.getItems();

    setState(() {
      _loadedAll = true;
      _loading = false;
    });

    _itemNotifier.value = items;
  }

  Future<void> _remoteSearchFetcher(String search) async {
    _filteredItemsNotifier.value = <T>[];
    _itemNotifier.value = <T>[];

    _setLoading(true);

    final fetcher = widget.fetcher as AppRemoteSearchListItemsFetcher<T>;
    final items = await fetcher.getItems(search);

    if (search != _lastSearch) {
      return;
    }

    _setLoading(false);

    _itemNotifier.value = items;
  }

  void _setLoading(bool loading) {
    if (loading == _loading) {
      return;
    }

    _loading = loading;
    _overlayEntry?.markNeedsBuild();
  }

  void _textControllerListener() {
    _searchDebouncer.run(
      () => _search(_textController.text),
    );
    _overlayEntry?.markNeedsBuild();
  }

  void _textFocusNodeListener() {
    if (mounted) {
      if (_textFocusNode.hasFocus) {
        if (_overlayEntry != null) {
          _textController.clear();
          Overlay.maybeOf(context)?.insert(_overlayEntry!);
        }
      } else {
        _overlayEntry?.remove();

        _setTextValue();
      }
    }
  }

  FutureOr<void> _onItemsChange() async {
    switch (widget.handler) {
      case AppSingleItemHandler<T>():
        (widget.handler as AppSingleItemHandler<T>).onChanged(
          _selectedItemNotifier.value.firstOrNull,
        );
        _textFocusNode.unfocus();

      case AppMultipleItemsHandler<T>():
        (widget.handler as AppMultipleItemsHandler<T>).onChanged(
          _selectedItemNotifier.value,
        );
    }

    _hasItemsNotifier.value = _selectedItemNotifier.value.isNotEmpty;

    if (!_hasItemsNotifier.value) {
      _setTextValue();
    }
  }

  void _afterLayout() {
    _setTextValue();

    if (_renderBox == null) {
      return;
    }

    _overlayEntry ??= OverlayEntry(
      maintainState: true,
      canSizeOverlay: true,
      builder: (context) {
        const maxHeight = 200.0;
        final widgetPosition = _renderBox!.localToGlobal(Offset.zero);
        final availableSpace = MediaQuery.of(context).size.height - widgetPosition.dy - _widgetSize!.height;

        final openAbove = availableSpace < 128;

        return Positioned(
          width: _widgetSize!.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            targetAnchor: openAbove ? Alignment.topLeft : Alignment.bottomLeft,
            offset: Offset(0, openAbove ? -_widgetSize!.height : 0),
            showWhenUnlinked: false,
            child: Material(
              type: MaterialType.transparency,
              child: _overlayContent(
                maxHeight: maxHeight,
                availableSpace: availableSpace,
                openAbove: openAbove,
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleItem(T? item) {
    return switch (widget.handler) {
      (AppSingleItemHandler<T>()) => _handleSingleItem(item),
      (AppMultipleItemsHandler<T>()) => _handleMultipleItems(item),
    };
  }

  void _handleSingleItem(T? item) {
    if (item == null) {
      _selectedItemNotifier.value = [];
    } else {
      _selectedItemNotifier.value = [item];
    }
  }

  void _handleMultipleItems(T? item) {
    final items = List.of(_selectedItemNotifier.value);

    if (item == null) {
      items.clear();
    } else {
      if (items.contains(item)) {
        items.remove(item);
      } else {
        items.add(item);
      }
    }

    _selectedItemNotifier.value = items;
  }

  void _setTextValue() {
    final items = _selectedItemNotifier.value;

    if (items.isEmpty) {
      _textController.clear();
    } else {
      final text = switch (widget.handler) {
        (AppSingleItemHandler<T>()) => widget.handler.asString(items.first),
        (AppMultipleItemsHandler<T>()) => items.length > 3
            ? '${items.length} items'
            : items.take(3).map((item) => widget.handler.asString(item)).join(', '),
      };

      _textController.text = text;
    }
  }

  @override
  void initState() {
    super.initState();

    _textController.addListener(_textControllerListener);
    _textFocusNode.addListener(_textFocusNodeListener);
    _selectedItemNotifier.addListener(_onItemsChange);

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _afterLayout(),
    );
  }

  @override
  void dispose() {
    _itemNotifier.dispose();
    _filteredItemsNotifier.dispose();
    _selectedItemNotifier.dispose();

    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppDropDownFormField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.fetcher != widget.fetcher) {
      _loadedAll = false;
      _itemNotifier.value = <T>[];
    }

    if (oldWidget.handler != widget.handler) {
      _selectedItemNotifier.value = switch (widget.handler) {
        (AppSingleItemHandler<T>()) => [
            (widget.handler as AppSingleItemHandler<T>).initialValue,
          ].whereNotNull().toList(),
        (AppMultipleItemsHandler<T>()) => (widget.handler as AppMultipleItemsHandler<T>).initialValue,
      };

      if (!_textFocusNode.hasFocus) {
        _setTextValue();
      }
    }
  }

  Widget _overlayContent({
    required double maxHeight,
    required double availableSpace,
    required bool openAbove,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_loading) const LinearProgressIndicator(),
        Flexible(
          child: TextFieldTapRegion(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              constraints: BoxConstraints(
                maxHeight: openAbove
                    ? maxHeight
                    : availableSpace > maxHeight
                        ? maxHeight
                        : availableSpace - 16,
              ),
              decoration: BoxDecoration(
                color: context.wpColorsConfig.surfaceContainer,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 10.0,
                    color: Colors.black.withOpacity(0.25),
                    offset: const Offset(5.0, 10.0),
                  ),
                ],
              ),
              child: ValueListenableBuilder<List<T>>(
                valueListenable: _filteredItemsNotifier,
                builder: (context, items, child) {
                  if (items.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Material(
                    type: MaterialType.transparency,
                    child: ListView.separated(
                      itemCount: items.length,
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      physics: const ClampingScrollPhysics(),
                      separatorBuilder: (context, index) => const Divider(height: 0),
                      itemBuilder: (context, index) {
                        final item = items[index];

                        return ListenableBuilder(
                          listenable: _selectedItemNotifier,
                          builder: (context, child) {
                            final selected = _selectedItemNotifier.value.any((selected) {
                              return widget.handler.compare(selected, item);
                            });

                            onTapItem() => _handleItem(item);

                            final textWg = Text(widget.handler.asString(item));
                            final padding = widget.tilesContentPadding;

                            if (widget.tileBuilder != null) {
                              return widget.tileBuilder!(item, selected, onTapItem);
                            }

                            return switch (widget.handler) {
                              (AppSingleItemHandler<T>()) => ListTile(
                                  key: ObjectKey(item),
                                  title: textWg,
                                  onTap: onTapItem,
                                  contentPadding: padding,
                                  selected: selected,
                                ),
                              (AppMultipleItemsHandler<T>()) => CheckboxListTile(
                                  key: ObjectKey(item),
                                  title: textWg,
                                  value: selected,
                                  onChanged: (_) => onTapItem(),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  contentPadding: padding,
                                ),
                            };
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: ValueListenableBuilder<bool>(
        valueListenable: _hasItemsNotifier,
        builder: (context, hasItems, child) {
          return AppTextFormField(
            enabled: widget.enabled,
            controller: _textController,
            focusNode: _textFocusNode,
            key: _widgetKey,
            labelText: widget.labelText,
            hintText: widget.hintText,
            border: widget.border,
            errorType: widget.errorType,
            contentPadding: widget.inputContentPadding,
            validator: widget.validator != null
                ? (_) {
                    return widget.validator!.validate(
                      _selectedItemNotifier.value,
                    );
                  }
                : null,
            suffixIcon: widget.showTrailing
                ? hasItems
                    ? AppButton.icon(
                        onPressed: () => _handleItem(null),
                        icon: const Icon(Icons.close),
                      )
                    : const Icon(Icons.arrow_drop_down)
                : null,
          );
        },
      ),
    );
  }
}
