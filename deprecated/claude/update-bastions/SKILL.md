---
name: update-bastions
description: Query AWS for running bastion EC2 instances and update the bastion tunnel shortcuts in ~/.zshrc with current instance IDs.
when-to-use: When the user wants to update bastion instance IDs, fix bastion tunnels, refresh bastion config, or says "update bastions".
argument-hint: "[dev|prod|all]"
user-invocable: true
---

# Update Bastions

Queries AWS EC2 for running bastion instances and updates the SSM tunnel shortcuts in `~/.zshrc` to point at the current instance IDs.

## Invocation

```
/update-bastions          # Update all bastion entries (dev + prod)
/update-bastions dev      # Update only bastion-dev
/update-bastions prod     # Update only bastion-prod
```

## Procedure

1. **Query AWS for running bastion instances:**

   ```bash
   aws ec2 describe-instances \
     --filters "Name=tag:Name,Values=*bastion*" "Name=instance-state-name,Values=running" \
     --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,ID:InstanceId,IP:PublicIpAddress,PrivateIP:PrivateIpAddress}" \
     --output table
   ```

2. **Parse the results.** Build a map of bastion name to instance ID from the output. If no instances are returned, stop and tell the user — do not modify `.zshrc`.

3. **Read `~/.zshrc`** and find the bastion function blocks (`bastion-dev()`, `bastion-prod()`, etc.). Extract the current `--target` instance IDs.

4. **Filter by argument.** If the user passed `dev` or `prod`, only process that entry. Otherwise process all.

5. **Compare instance IDs.** For each bastion function:
   - If the `.zshrc` instance ID matches the running instance, report it as already up to date.
   - If they differ, update the `--target` value in `.zshrc` using the Edit tool.

6. **Source the config:**

   ```bash
   source ~/.zshrc
   ```

7. **Report a summary** showing, for each bastion:
   - Name
   - Old instance ID (if changed)
   - New instance ID
   - Private IP
   - Whether it was updated or already current

## Important rules

- **Never delete or rewrite bastion functions.** Only update the `--target` instance ID value within existing functions.
- **Do not touch other parts of `.zshrc`.** Use targeted Edit calls, not full file rewrites.
- If AWS CLI fails (credentials, permissions, network), stop and tell the user — do not modify `.zshrc`.
- If a bastion name from AWS doesn't have a matching function in `.zshrc`, inform the user but do not create a new function unless asked.
