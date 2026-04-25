/// 场景包（V1.1）：意图 × 对象，作为附加 system 提示。
class ScenarioPack {
  const ScenarioPack({required this.key, required this.label, required this.hint});

  final String key;
  final String label;
  final String hint;

  static const List<ScenarioPack> all = [
    ScenarioPack(
      key: 'leave_teacher',
      label: '请假·对导师',
      hint: '学生向导师请假：说明原因、时间安排、补救学习计划，语气尊敬克制。',
    ),
    ScenarioPack(
      key: 'push_colleague',
      label: '催进度·对同事',
      hint: '同事协作催进度：先肯定贡献，再明确截止与依赖，避免指责。',
    ),
    ScenarioPack(
      key: 'reject_sales',
      label: '婉拒·对销售',
      hint: '婉拒推销：感谢+明确不需要+礼貌收尾，不留暧昧空间。',
    ),
    ScenarioPack(
      key: 'none',
      label: '无特定场景',
      hint: '',
    ),
  ];

  static ScenarioPack? byKey(String? key) {
    if (key == null || key.isEmpty) return null;
    for (final s in all) {
      if (s.key == key) return s;
    }
    return null;
  }
}
