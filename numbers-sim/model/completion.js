export function evaluateTasks(spec, sales, menuComplete, dishCount) {
  if (spec == null || (Array.isArray(spec) && spec.length === 0)) return null;
  if (!Array.isArray(spec)) throw new TypeError('Task specification must be an array');
  const tasks = spec.map(task => {
    if ((task.type != null && task.type !== 'sales') || !Number.isInteger(task.dish) || task.dish < 0 || task.dish >= dishCount || !Number.isInteger(task.target) || task.target <= 0)
      throw new RangeError('Only positive sales targets for known dish indices are supported');
    const sold = sales[task.dish] ?? 0;
    return { ...task, sold, done: sold + 1e-9 >= task.target };
  });
  return { done: menuComplete && tasks.every(t => t.done), tasks };
}
export function secondsToTasks(spec, sales, rates, menuComplete) {
  if (!menuComplete || !spec?.length) return Infinity;
  return Math.max(0, ...spec.map(task => {
    const remaining = task.target - (sales[task.dish] ?? 0);
    if (remaining <= 1e-9) return 0;
    const rate = rates[task.dish] ?? 0;
    return rate > 0 ? remaining / rate : Infinity;
  }));
}
