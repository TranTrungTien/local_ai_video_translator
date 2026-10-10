enum AiTaskPriority {
  p0PlaybackCritical,
  p1CurrentSubtitle,
  p2NextSubtitleWindow,
  p3TargetLookahead,
  p4Dub,
  p5DistantCache,
}

class AiTaskItem implements Comparable<AiTaskItem> {
  const AiTaskItem({
    required this.id,
    required this.priority,
    required this.action,
    required this.targetPts,
  });

  final String id;
  final AiTaskPriority priority;
  final Future<void> Function() action;
  final Duration targetPts;

  @override
  int compareTo(AiTaskItem other) {
    return priority.index.compareTo(other.priority.index);
  }
}

class TaskPriorityQueue {
  final List<AiTaskItem> _tasks = [];

  int get length => _tasks.length;
  bool get isEmpty => _tasks.isEmpty;

  void enqueue(AiTaskItem task) {
    _tasks.add(task);
    _tasks.sort();
  }

  AiTaskItem? dequeue() {
    if (_tasks.isEmpty) return null;
    return _tasks.removeAt(0);
  }

  void cancelObsoleteTasks(Duration currentPts) {
    // Remove background lookahead tasks far behind or irrelevant after seek
    _tasks.removeWhere(
      (t) =>
          t.priority.index >= AiTaskPriority.p3TargetLookahead.index &&
          t.targetPts < currentPts,
    );
  }

  void clear() {
    _tasks.clear();
  }
}
