import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:infinite_scroll_pagination/src/model/paging_state.dart';
import 'package:infinite_scroll_pagination/src/model/paging_status.dart';
import 'package:infinite_scroll_pagination/src/ui/default_indicators/empty_list_indicator.dart';
import 'package:infinite_scroll_pagination/src/ui/default_indicators/first_page_error_indicator.dart';
import 'package:infinite_scroll_pagination/src/ui/default_indicators/first_page_progress_indicator.dart';
import 'package:infinite_scroll_pagination/src/ui/default_indicators/new_page_error_indicator.dart';
import 'package:infinite_scroll_pagination/src/ui/default_indicators/new_page_progress_indicator.dart';
import 'package:infinite_scroll_pagination/src/workers/paging_controller.dart';

typedef CompletedListingBuilder = Widget Function(
  BuildContext context,
  IndexedWidgetBuilder itemWidgetBuilder,
  int itemCount,
);

typedef ErrorListingBuilder = Widget Function(
  BuildContext context,
  IndexedWidgetBuilder itemWidgetBuilder,
  int itemCount,
  WidgetBuilder newPageErrorIndicatorBuilder,
);

typedef LoadingListingBuilder = Widget Function(
  BuildContext context,
  IndexedWidgetBuilder itemWidgetBuilder,
  int itemCount,
  WidgetBuilder newPageProgressIndicatorBuilder,
);

/// Helps creating infinitely scrolled paged sliver widgets.
///
/// Combines a [PagedDataSource] with a
/// [PagedChildBuilderDelegate] and calls the supplied
/// [loadingListingBuilder], [errorListingBuilder] or
/// [completedListingBuilder] to fill in the gaps.
///
/// For ordinary cases, this widget shouldn't be used directly. Instead, take a
/// look at [PagedSliverList], [PagedSliverGrid],
/// [PagedGridView] and [PagedListView].
class PagedSliverBuilder<PageKeyType, ItemType> extends StatefulWidget {
  const PagedSliverBuilder({
    @required this.pagingController,
    @required this.builderDelegate,
    @required this.loadingListingBuilder,
    @required this.errorListingBuilder,
    @required this.completedListingBuilder,
    Key key,
  })  : assert(pagingController != null),
        assert(builderDelegate != null),
        assert(loadingListingBuilder != null),
        assert(errorListingBuilder != null),
        assert(completedListingBuilder != null),
        super(key: key);

  /// The data source for paged listings.
  ///
  /// Fetches new items, tells what are the currently loaded ones, what's the
  /// next page's key and whether there is an error.
  ///
  /// This object should generally have a lifetime longer than the
  /// widgets itself; it should be reused each time a paged widget
  /// constructor is called.
  final PagingController<PageKeyType, ItemType> pagingController;

  /// The delegate for building UI pieces of scrolling paged listings.
  final PagedChildBuilderDelegate<ItemType> builderDelegate;

  /// The builder for an in-progress listing.
  final LoadingListingBuilder loadingListingBuilder;

  /// The builder for an in-progress listing with a failed request.
  final ErrorListingBuilder errorListingBuilder;

  /// The builder for a completed listing.
  final CompletedListingBuilder completedListingBuilder;

  @override
  _PagedSliverBuilderState<PageKeyType, ItemType> createState() =>
      _PagedSliverBuilderState<PageKeyType, ItemType>();
}

class _PagedSliverBuilderState<PageKeyType, ItemType>
    extends State<PagedSliverBuilder<PageKeyType, ItemType>> {
  PagingController<PageKeyType, ItemType> get _pagingController =>
      widget.pagingController;

  PagedChildBuilderDelegate<ItemType> get _builderDelegate =>
      widget.builderDelegate;

  WidgetBuilder get _firstPageErrorIndicatorBuilder =>
      _builderDelegate.firstPageErrorIndicatorBuilder ??
      (_) => FirstPageErrorIndicator(
            onTryAgain: _pagingController.refresh,
          );

  WidgetBuilder get _newPageErrorIndicatorBuilder =>
      _builderDelegate.newPageErrorIndicatorBuilder ??
      (_) => NewPageErrorIndicator(
            onTap: _pagingController.retryLastRequest,
          );

  WidgetBuilder get _firstPageProgressIndicatorBuilder =>
      _builderDelegate.firstPageProgressIndicatorBuilder ??
      (_) => FirstPageProgressIndicator();

  WidgetBuilder get _newPageProgressIndicatorBuilder =>
      _builderDelegate.newPageProgressIndicatorBuilder ??
      (_) => const NewPageProgressIndicator();

  WidgetBuilder get _noItemsFoundIndicatorBuilder =>
      _builderDelegate.noItemsFoundIndicatorBuilder ??
      (_) => EmptyListIndicator();

  int get _invisibleItemsThreshold =>
      _pagingController.invisibleItemsThreshold ?? 3;

  int get _itemCount => _pagingController.itemCount;

  bool get _hasNextPage => _pagingController.hasNextPage;

  PageKeyType get _nextKey => _pagingController.nextPageKey;

  /// The index that triggered the last page request.
  ///
  /// Used to avoid duplicate requests on rebuilds.
  int _lastFetchTriggerIndex;

  @override
  void initState() {
    _requestNextPage(0);
    super.initState();
  }

  @override
  Widget build(BuildContext context) =>
      // The SliverPadding is used to avoid changing the topmost item inside a
      // CustomScrollView.
      // https://github.com/flutter/flutter/issues/55170
      SliverPadding(
        padding: const EdgeInsets.all(0),
        sliver: ValueListenableBuilder<PagingState<PageKeyType, ItemType>>(
          valueListenable: _pagingController,
          builder: (context, pagingState, _) {
            switch (pagingState.status) {
              case PagingStatus.ongoing:
                return widget.loadingListingBuilder(
                  context,
                  _buildListItemWidget,
                  _itemCount,
                  _newPageProgressIndicatorBuilder,
                );
              case PagingStatus.completed:
                return widget.completedListingBuilder(
                  context,
                  _buildListItemWidget,
                  _itemCount,
                );
              case PagingStatus.loadingFirstPage:
                _lastFetchTriggerIndex = null;
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _firstPageProgressIndicatorBuilder(context),
                );
              case PagingStatus.subsequentPageError:
                return widget.errorListingBuilder(
                  context,
                  _buildListItemWidget,
                  _itemCount,
                  (context) => _newPageErrorIndicatorBuilder(context),
                );
              case PagingStatus.empty:
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _noItemsFoundIndicatorBuilder(context),
                );
              default:
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _firstPageErrorIndicatorBuilder(context),
                );
            }
          },
        ),
      );

  /// Connects the [_pagingController] with the [_builderDelegate] in order to create
  /// a list item widget and request new items if needed.
  Widget _buildListItemWidget(
    BuildContext context,
    int index,
  ) {
    final item = _pagingController.itemList[index];

    final newFetchTriggerIndex = _itemCount - _invisibleItemsThreshold;

    final hasRequestedPageForTriggerIndex =
        newFetchTriggerIndex == _lastFetchTriggerIndex;

    final isThresholdBiggerThanListSize = newFetchTriggerIndex < 0;

    final isCurrentIndexEqualToTriggerIndex = index == newFetchTriggerIndex;

    final isCurrentIndexEligibleForItemsFetch =
        isThresholdBiggerThanListSize || isCurrentIndexEqualToTriggerIndex;

    if (_hasNextPage &&
        isCurrentIndexEligibleForItemsFetch &&
        !hasRequestedPageForTriggerIndex) {
      _requestNextPage(newFetchTriggerIndex);
    }

    final itemWidget = _builderDelegate.itemBuilder(context, item, index);
    return itemWidget;
  }

  /// Requests a new page from the data source.
  void _requestNextPage(int triggerIndex) {
    _lastFetchTriggerIndex = triggerIndex;
    _pagingController.notifyPageRequestListeners(_nextKey);
  }
}
