## What

<!-- One or two sentences: what changed and why. -->

## Ticket

<!-- Link to the relevant ticket, e.g. docs/tickets/02-install-generator.md -->

## How

<!-- Brief explanation of the approach taken. Skip if the diff is self-evident. -->

## Testing

- [ ] `bundle exec rake test` passes
- [ ] Coverage ≥ 95%
- [ ] New behaviour is covered by tests

## Checklist

- [ ] Migration is reversible (or intentionally irreversible with a comment)
- [ ] No N+1 queries introduced
- [ ] No secrets or credentials committed
- [ ] `.gitignore` updated if new generated/tmp paths were added
