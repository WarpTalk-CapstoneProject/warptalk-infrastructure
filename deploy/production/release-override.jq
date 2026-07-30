{
  services: (
    reduce .images[] as $image ({};
      if ($base[0].services | has($image.service))
      then .[$image.service] = {
        image: ($image.ref + "@" + $image.digest)
      }
      else .
      end
    )
  )
}
