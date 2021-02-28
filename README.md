# Build-Automation_MiSTer

Automatic builds for your core repository.

## How to Use

1. Add the [ci_build.yml](templates/ci_build.yml) file to your repository at the path `.github/workflows/ci_build.yml`. After this, builds will be triggered automatically after a *push*.
2. In case you want to tigger Discord notifications, add a [secret](https://docs.github.com/en/actions/reference/encrypted-secrets#creating-encrypted-secrets-for-a-repository) named `DISCORD_NIGHTLIES_WEBHOOK_URL` with your webhook URL to your repository. *(optional)*
3. When the build is ready (check the **Actions** tab of your repository to see the job progress), find your `.rbf` file in the **Releases** page of your repository.

## FAQ

* **Can I trigger the builds manually?**

Yes, for that you need to go to the **Actions** tab, select the *workflow* named `CI Build` in the left panel, and press on the button that says "Run workflow" on the top of the right panel.


* **Can I deactivate the automatic builds, so that I can just use the manually triggered builds instead?**

Yes, just go to the `ci_build.yml` file that you added to your repository, and comment (`#`) the 4th line, so that it looks like this:
```
#  push:
```


* **Is this CI file 100% safe?**

As-is, this is a *use at your own risk* kind of file. By adding it like that, you are trusting the maintainers of **MiSTer-unstable-nightlies** to not do anything unexpected (we won't). But if you prefer to be in **total control**, and thus not incur in any risk, then you can fork this repository, and use your fork instead inside the `ci_build.yml` file.
For that, you have to replace the line that includes the string `https://raw.githubusercontent.com/MiSTer-unstable-nightlies/Build-Automation_MiSTer/main/build.sh` to another URL pointing to that same script but in your fork instead.


* **Some core doesn't work, what can I do?**

Some cores need some specific tweaking added at the [repositories.ini](repositories.ini) file. If you have a core that doesn't work consistently, maybe we will have to add it there with some specific parameters. Open an **Issue** to let us know, and we will look into it.


* **Can we add another Webhook / Notification / Post-Trigger action to the system?**

Probably not. Maybe at some point if it makes sense.


## License

Copyright © 2021, [José Manuel Barroso Galindo](https://twitter.com/josembarroso) aka *theypsilon*. 
Released under the [GPL v3 License](LICENSE).
