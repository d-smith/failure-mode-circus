data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Shared across every scenario: pulls images from ECR, ships logs to
# CloudWatch. Identical permissions everywhere, so it's created once (in the
# hub) and referenced by scenarios rather than recreated per-scenario.
resource "aws_iam_role" "execution" {
  count = var.create_execution_role ? 1 : 0

  name               = "${var.name_prefix}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = merge(var.tags, { Name = "${var.name_prefix}-ecs-task-execution" })
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  count = var.create_execution_role ? 1 : 0

  role       = aws_iam_role.execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Per-scenario task role factory: one role per key in var.task_roles, scoped
# to only the managed policies that scenario lists (none by default).
resource "aws_iam_role" "task" {
  for_each = var.task_roles

  name               = "${var.name_prefix}-${each.key}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}-task" })
}

locals {
  task_role_policy_attachments = merge([
    for role_key, role in var.task_roles : {
      for arn in role.managed_policy_arns : "${role_key}::${arn}" => {
        role_key = role_key
        arn      = arn
      }
    }
  ]...)
}

resource "aws_iam_role_policy_attachment" "task_managed" {
  for_each = local.task_role_policy_attachments

  role       = aws_iam_role.task[each.value.role_key].name
  policy_arn = each.value.arn
}
